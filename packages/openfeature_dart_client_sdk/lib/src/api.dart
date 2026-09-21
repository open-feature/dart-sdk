import 'dart:async';
import 'dart:collection';

import 'details.dart';
import 'error.dart';
import 'evaluation_context.dart';
import 'events.dart';
import 'hooks.dart';
import 'metadata.dart';
import 'no_op_provider.dart';
import 'provider.dart';

/// Creates an API instance isolated from the process-wide singleton.
///
/// This function is exported only from the experimental library.
OpenFeatureAPI createIsolatedOpenFeatureAPI({
  Duration lifecycleTimeout = const Duration(seconds: 30),
}) => OpenFeatureAPI._(lifecycleTimeout: lifecycleTimeout);

/// The static-context OpenFeature API.
final class OpenFeatureAPI {
  OpenFeatureAPI._({this.lifecycleTimeout = const Duration(seconds: 30)});

  /// The process-wide default API instance.
  static final OpenFeatureAPI instance = OpenFeatureAPI._();

  static const FeatureProvider _noOpProvider = NoOpProvider();
  static final Map<FeatureProvider, OpenFeatureAPI> _providerOwners =
      HashMap<FeatureProvider, OpenFeatureAPI>.identity();
  static final Expando<bool> _quarantinedProviders = Expando<bool>(
    'openfeature_quarantined_provider',
  );

  /// Maximum time allowed for one provider lifecycle operation.
  final Duration lifecycleTimeout;

  FeatureProvider _defaultProvider = _noOpProvider;
  final Map<String, FeatureProvider> _domainProviders =
      <String, FeatureProvider>{};
  EvaluationContext _globalContext = EvaluationContext.empty;
  final Map<String, EvaluationContext> _domainContexts =
      <String, EvaluationContext>{};
  final List<Hook> _hooks = <Hook>[];
  final List<_EventHandlerRecord> _eventHandlers = <_EventHandlerRecord>[];
  final Map<FeatureProvider, _ProviderRecord> _providerRecords =
      HashMap<FeatureProvider, _ProviderRecord>.identity();
  final Map<String?, Future<void>> _bindingMutationQueues =
      <String?, Future<void>>{};
  final Map<FeatureProvider, Future<void>> _providerMutationQueues =
      HashMap<FeatureProvider, Future<void>>.identity();
  final Set<String> _knownDomains = <String>{};
  final Set<String> _projectedDomainContexts = <String>{};
  final Map<String, int> _domainContextRevisions = <String, int>{};

  /// Adds API hooks without removing existing hooks.
  void addHooks(Iterable<Hook> hooks) => _hooks.addAll(hooks);

  /// Adds an API-wide handler for [eventType].
  ///
  /// The handler remains registered across provider changes.
  ProviderEventSubscription addHandler(
    ProviderEventType eventType,
    ProviderEventHandler handler,
  ) {
    return _addHandler(eventType, handler, domain: null, apiWide: true);
  }

  /// Removes a previously registered API or client event handler.
  void removeHandler(ProviderEventSubscription subscription) {
    subscription.cancel();
  }

  /// Gets a client bound to [domain], or to the default provider when omitted.
  OpenFeatureClient getClient([String? domain]) {
    return OpenFeatureClient._(this, ClientMetadata(domain: domain));
  }

  /// Gets metadata for the provider selected by [domain].
  ProviderMetadata getProviderMetadata([String? domain]) {
    return _providerForDomain(domain).metadata;
  }

  /// Starts registration of the default provider.
  void setProvider(FeatureProvider provider) {
    unawaited(setProviderAndWait(provider).catchError((Object _) {}));
  }

  /// Registers the default provider after its initialization terminates.
  Future<void> setProviderAndWait(FeatureProvider provider) {
    return _enqueueBindingMutations([null], () {
      final current = _providerForExactBinding(null);
      return _enqueueProviderMutations([
        current,
        provider,
      ], () => _setProvider(provider, domain: null));
    });
  }

  /// Starts registration of [provider] for [domain].
  void setProviderForDomain(String domain, FeatureProvider provider) {
    unawaited(
      setProviderForDomainAndWait(domain, provider).catchError((Object _) {}),
    );
  }

  /// Registers [provider] for [domain] after initialization terminates.
  Future<void> setProviderForDomainAndWait(
    String domain,
    FeatureProvider provider,
  ) {
    _knownDomains.add(domain);
    final globalPredecessor = _projectedDomainContexts.contains(domain)
        ? null
        : _bindingMutationQueues[null];
    return _enqueueBindingMutations([domain], () async {
      if (globalPredecessor != null) {
        await globalPredecessor.catchError((Object _) {});
      }
      final current = _providerForExactBinding(domain);
      return _enqueueProviderMutations([
        current,
        provider,
      ], () => _setProvider(provider, domain: domain));
    });
  }

  /// Starts a global context change.
  void setEvaluationContext(EvaluationContext context) {
    unawaited(setEvaluationContextAndWait(context).catchError((Object _) {}));
  }

  /// Sets the global static evaluation context.
  Future<void> setEvaluationContextAndWait(EvaluationContext context) {
    final affectedBindings = <String?>[
      null,
      ..._knownDomains.where(
        (domain) =>
            !_domainContexts.containsKey(domain) ||
            !_projectedDomainContexts.contains(domain),
      ),
    ];
    return _enqueueBindingMutations(affectedBindings, () {
      final providers = _providersUsingGlobalContext();
      return _enqueueProviderMutations(
        providers,
        () => _setGlobalContext(context, providers),
      );
    });
  }

  Set<FeatureProvider> _providersUsingGlobalContext() {
    return HashSet<FeatureProvider>.identity()
      ..add(_defaultProvider)
      ..addAll(
        _domainProviders.entries
            .where((entry) => !_domainContexts.containsKey(entry.key))
            .map((entry) => entry.value),
      )
      ..remove(_noOpProvider);
  }

  Future<void> _setGlobalContext(
    EvaluationContext context,
    Set<FeatureProvider> providers,
  ) async {
    final previousContext = _globalContext;

    final outcomes = await Future.wait(
      providers.map((provider) async {
        try {
          final reconciliation = await _reconcile(provider, context);
          return (
            provider: provider,
            reconciliation: reconciliation,
            error: null,
            stackTrace: null,
          );
        } on Object catch (error, stackTrace) {
          return (
            provider: provider,
            reconciliation: null,
            error: error,
            stackTrace: stackTrace,
          );
        }
      }),
    );
    final failures = outcomes.where((outcome) => outcome.error != null);
    if (failures.isNotEmpty) {
      final successfulOutcomes = outcomes.where(
        (outcome) => outcome.error == null,
      );
      for (final outcome in successfulOutcomes) {
        _dispatchReconciliationEvent(outcome.provider, outcome.reconciliation);
      }
      await Future.wait(
        successfulOutcomes.map((outcome) async {
          try {
            final rollback = await _reconcile(
              outcome.provider,
              previousContext,
            );
            _dispatchReconciliationEvent(outcome.provider, rollback);
          } on Object {
            final record = _providerRecords[outcome.provider];
            if (record != null) {
              await _quarantineProvider(outcome.provider, record);
            }
          }
        }),
      );
      final failure = failures.first;
      Error.throwWithStackTrace(failure.error!, failure.stackTrace!);
    }
    _globalContext = context;
    for (final outcome in outcomes) {
      _dispatchReconciliationEvent(outcome.provider, outcome.reconciliation);
    }
  }

  /// Starts a context change for [domain].
  void setEvaluationContextForDomain(String domain, EvaluationContext context) {
    unawaited(
      setEvaluationContextForDomainAndWait(
        domain,
        context,
      ).catchError((Object _) {}),
    );
  }

  /// Sets the static evaluation context for [domain].
  Future<void> setEvaluationContextForDomainAndWait(
    String domain,
    EvaluationContext context,
  ) {
    _knownDomains.add(domain);
    _projectedDomainContexts.add(domain);
    final revision = (_domainContextRevisions[domain] ?? 0) + 1;
    _domainContextRevisions[domain] = revision;
    return _enqueueBindingMutations([domain], () {
      final provider = _providerForExactBinding(domain);
      return _enqueueProviderMutations([provider], () async {
        try {
          await _setDomainContext(domain, context);
        } on Object {
          _restoreProjectedDomainContext(domain, revision);
          rethrow;
        }
      });
    });
  }

  Future<void> _setDomainContext(
    String domain,
    EvaluationContext context,
  ) async {
    final provider = _domainProviders[domain];
    _ReconciliationResult? reconciliation;
    if (provider != null) {
      reconciliation = await _reconcile(provider, context);
    }
    _domainContexts[domain] = context;
    if (provider != null) {
      _dispatchReconciliationEvent(provider, reconciliation);
    }
  }

  /// Clears a domain context and restores global-context fallback.
  Future<void> clearEvaluationContextForDomainAndWait(String domain) {
    _knownDomains.add(domain);
    _projectedDomainContexts.remove(domain);
    final revision = (_domainContextRevisions[domain] ?? 0) + 1;
    _domainContextRevisions[domain] = revision;
    return _enqueueBindingMutations([domain], () {
      final provider = _providerForExactBinding(domain);
      return _enqueueProviderMutations([provider], () async {
        try {
          await _clearDomainContext(domain);
        } on Object {
          _restoreProjectedDomainContext(domain, revision);
          rethrow;
        }
      });
    });
  }

  void _restoreProjectedDomainContext(String domain, int revision) {
    if (_domainContextRevisions[domain] != revision) {
      return;
    }
    if (_domainContexts.containsKey(domain)) {
      _projectedDomainContexts.add(domain);
    } else {
      _projectedDomainContexts.remove(domain);
    }
  }

  Future<void> _clearDomainContext(String domain) async {
    final provider = _domainProviders[domain];
    _ReconciliationResult? reconciliation;
    if (provider != null && _domainContexts.containsKey(domain)) {
      reconciliation = await _reconcile(provider, _globalContext);
    }
    _domainContexts.remove(domain);
    if (provider != null) {
      _dispatchReconciliationEvent(provider, reconciliation);
    }
  }

  /// Starts clearing a domain context.
  void clearEvaluationContextForDomain(String domain) {
    unawaited(
      clearEvaluationContextForDomainAndWait(domain).catchError((Object _) {}),
    );
  }

  /// Shuts down all active providers and resets API state.
  Future<void> shutdown() {
    return _enqueueBindingMutations([null, ..._knownDomains], () {
      return _enqueueProviderMutations(_providerRecords.keys, _shutdown);
    });
  }

  Future<void> _shutdown() async {
    final records = _providerRecords.entries.toList(growable: false);
    _defaultProvider = _noOpProvider;
    _domainProviders.clear();
    _domainContexts.clear();
    _knownDomains.clear();
    _projectedDomainContexts.clear();
    _domainContextRevisions.clear();
    _globalContext = EvaluationContext.empty;
    _hooks.clear();
    for (final handler in _eventHandlers) {
      handler.subscription._deactivate();
    }
    _eventHandlers.clear();

    try {
      await Future.wait(
        records.map((entry) async {
          await _disposeProvider(entry.key, entry.value);
        }),
      );
    } finally {
      _providerRecords.clear();
    }
  }

  FeatureProvider _providerForDomain(String? domain) {
    if (domain == null) {
      return _defaultProvider;
    }
    return _domainProviders[domain] ?? _defaultProvider;
  }

  EvaluationContext _contextForDomain(String? domain) {
    final provider = _providerForExactBinding(domain);
    if (identical(provider, _noOpProvider)) {
      return _globalContext;
    }
    final record = _providerRecords[provider];
    if (provider is ContextReconciliationProvider && record != null) {
      return record.activeContext;
    }
    return _requestedContextForDomain(domain);
  }

  EvaluationContext _requestedContextForDomain(String? domain) {
    if (domain == null) {
      return _globalContext;
    }
    return _domainContexts[domain] ?? _globalContext;
  }

  ProviderStatus _statusForDomain(String? domain) {
    final provider = _providerForDomain(domain);
    if (identical(provider, _noOpProvider)) {
      return ProviderStatus.notReady;
    }
    return _providerRecords[provider]?.status ?? ProviderStatus.notReady;
  }

  Future<void> _setProvider(
    FeatureProvider provider, {
    required String? domain,
  }) async {
    if (_quarantinedProviders[provider] == true) {
      throw const OpenFeatureException(
        'A provider instance that timed out cannot be reused. '
        'Create a replacement provider instance.',
      );
    }
    final current = _providerForExactBinding(domain);
    if (identical(current, provider)) {
      return;
    }
    _validateDomainScope(provider, domain);

    var record = _providerRecords[provider];
    Object? initializationError;
    StackTrace? initializationStackTrace;
    if (record == null) {
      final owner = _providerOwners[provider];
      if (owner != null && !identical(owner, this)) {
        throw const OpenFeatureException(
          'A provider instance cannot be active in more than one API instance.',
        );
      }
      record = _ProviderRecord(
        initialDomain: domain,
        metadata: provider.metadata,
        activeContext: _requestedContextForDomain(domain),
      );
      _providerOwners[provider] = this;
      _providerRecords[provider] = record;
      try {
        await _initialize(provider, record, domain);
      } on Object catch (error, stackTrace) {
        if (record.quarantined ||
            (record.status != ProviderStatus.error &&
                record.status != ProviderStatus.fatal)) {
          try {
            await _disposeProvider(provider, record);
          } on Object {
            // Preserve the initialization failure when cleanup also fails.
          }
          Error.throwWithStackTrace(error, stackTrace);
        }
        initializationError = error;
        initializationStackTrace = stackTrace;
      }
    } else if (provider is ContextReconciliationProvider &&
        record.bindingCount > 0) {
      throw const OpenFeatureException(
        'A context-reconciling provider can have only one active binding. '
        'Use a separate provider instance for each independently scoped context.',
      );
    }

    if (domain == null) {
      _defaultProvider = provider;
    } else {
      _domainProviders[domain] = provider;
    }
    record.bindingCount++;
    for (final event in record.pendingBindingEvents) {
      _dispatchEvent(provider, record, event);
    }
    record.pendingBindingEvents.clear();

    if (!identical(current, _noOpProvider)) {
      await _releaseProvider(current);
    }
    if (initializationError != null) {
      Error.throwWithStackTrace(initializationError, initializationStackTrace!);
    }
  }

  FeatureProvider _providerForExactBinding(String? domain) {
    if (domain == null) {
      return _defaultProvider;
    }
    return _domainProviders[domain] ?? _noOpProvider;
  }

  void _validateDomainScope(FeatureProvider provider, String? domain) {
    if (provider is! DomainScopedProvider) {
      return;
    }
    final record = _providerRecords[provider];
    if (record != null &&
        record.bindingCount > 0 &&
        record.initialDomain != domain) {
      throw const OpenFeatureException(
        'A domain-scoped provider can be bound to only one domain.',
      );
    }
  }

  Future<T> _enqueueBindingMutations<T>(
    Iterable<String?> domains,
    Future<T> Function() operation,
  ) {
    final keys = domains.toSet();
    final predecessors = keys
        .map((key) => _bindingMutationQueues[key] ?? Future<void>.value())
        .toSet();
    final result = Future.wait(
      predecessors.map((future) => future.catchError((Object _) {})),
    ).then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    for (final key in keys) {
      _bindingMutationQueues[key] = tail;
    }
    unawaited(
      tail.then((_) {
        for (final key in keys) {
          if (identical(_bindingMutationQueues[key], tail)) {
            _bindingMutationQueues.remove(key);
          }
        }
      }),
    );
    return result;
  }

  Future<T> _enqueueProviderMutations<T>(
    Iterable<FeatureProvider> providers,
    Future<T> Function() operation,
  ) {
    final keys = HashSet<FeatureProvider>.identity()
      ..addAll(providers)
      ..remove(_noOpProvider);
    final predecessors = keys
        .map((key) => _providerMutationQueues[key] ?? Future<void>.value())
        .toSet();
    final result = Future.wait(
      predecessors.map((future) => future.catchError((Object _) {})),
    ).then((_) => operation());
    final tail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    for (final key in keys) {
      _providerMutationQueues[key] = tail;
    }
    unawaited(
      tail.then((_) {
        for (final key in keys) {
          if (identical(_providerMutationQueues[key], tail)) {
            _providerMutationQueues.remove(key);
          }
        }
      }),
    );
    return result;
  }

  Future<void> _initialize(
    FeatureProvider provider,
    _ProviderRecord record,
    String? domain,
  ) async {
    if (provider is ProviderEventSource) {
      record.eventSubscription = (provider as ProviderEventSource).events
          .listen((event) => _processEvent(provider, record, event));
    }

    if (provider is! InitializableProvider) {
      _processEvent(
        provider,
        record,
        ProviderEvent(type: ProviderEventType.ready),
      );
      return;
    }
    if (provider is! ProviderEventSource) {
      throw const OpenFeatureException(
        'A provider with initialize() must expose provider events.',
      );
    }

    final operation = _LifecycleOperation(ProviderEventType.ready);
    record.lifecycleOperation = operation;
    var timedOut = false;
    try {
      final status =
          await (() async {
            await (provider as InitializableProvider).initialize(
              _requestedContextForDomain(domain),
              domain: domain,
            );
            operation.completeCallback();
            return operation.future;
          })().timeout(
            lifecycleTimeout,
            onTimeout: () {
              timedOut = true;
              throw OpenFeatureException(
                'Provider initialization did not complete within '
                '${lifecycleTimeout.inMilliseconds} ms.',
              );
            },
          );
      if (status == ProviderStatus.error || status == ProviderStatus.fatal) {
        throw OpenFeatureException(
          'Provider initialization ended with status ${status.name}.',
          errorCode: status == ProviderStatus.fatal
              ? ErrorCode.providerFatal
              : ErrorCode.general,
        );
      }
    } on Object {
      if (timedOut) {
        _markProviderQuarantined(provider, record);
      }
      rethrow;
    } finally {
      if (identical(record.lifecycleOperation, operation)) {
        record.lifecycleOperation = null;
      }
    }
  }

  Future<_ReconciliationResult?> _reconcile(
    FeatureProvider provider,
    EvaluationContext newContext,
  ) async {
    if (provider is! ContextReconciliationProvider) {
      final record = _providerRecords[provider];
      if (record != null) {
        record.activeContext = newContext;
      }
      return null;
    }
    if (provider is! ProviderEventSource) {
      throw const OpenFeatureException(
        'A provider with onContextChanged() must expose provider events.',
      );
    }

    final record = _providerRecords[provider];
    if (record == null) {
      return null;
    }
    final previousContext = record.activeContext;
    final operation = _LifecycleOperation(ProviderEventType.contextChanged);
    record.lifecycleOperation = operation;
    var timedOut = false;
    try {
      final status =
          await (() async {
            await (provider as ContextReconciliationProvider).onContextChanged(
              previousContext,
              newContext,
            );
            operation.completeCallback();
            return operation.future;
          })().timeout(
            lifecycleTimeout,
            onTimeout: () {
              timedOut = true;
              throw OpenFeatureException(
                'Provider reconciliation did not complete within '
                '${lifecycleTimeout.inMilliseconds} ms.',
              );
            },
          );
      if (status == ProviderStatus.error || status == ProviderStatus.fatal) {
        throw OpenFeatureException(
          'Provider reconciliation ended with status ${status.name}.',
          errorCode: status == ProviderStatus.fatal
              ? ErrorCode.providerFatal
              : ErrorCode.general,
        );
      }
      record.activeContext = newContext;
      final terminalEvent = operation.terminalEvent;
      if (terminalEvent == null ||
          terminalEvent.type != ProviderEventType.contextChanged) {
        throw const OpenFeatureException(
          'Provider reconciliation completed without a context-changed event.',
        );
      }
      return _ReconciliationResult(record, terminalEvent);
    } on Object catch (error, stackTrace) {
      if (timedOut) {
        await _quarantineProvider(provider, record);
        Error.throwWithStackTrace(error, stackTrace);
      }
      rethrow;
    } finally {
      if (identical(record.lifecycleOperation, operation)) {
        record.lifecycleOperation = null;
      }
    }
  }

  void _processEvent(
    FeatureProvider provider,
    _ProviderRecord record,
    ProviderEvent event,
  ) {
    if (record.quarantined || !identical(_providerRecords[provider], record)) {
      return;
    }
    final operation = record.lifecycleOperation;
    if (event.type == ProviderEventType.contextChanged &&
        operation?.successEventType == ProviderEventType.contextChanged) {
      operation!.observe(event, ProviderStatus.ready);
      return;
    }
    _applyEventState(record, event);

    if (record.bindingCount == 0) {
      record.pendingBindingEvents.add(event);
    } else {
      _dispatchEvent(provider, record, event);
    }

    operation?.observe(event, record.status);
  }

  void _applyEventState(_ProviderRecord record, ProviderEvent event) {
    switch (event.type) {
      case ProviderEventType.ready:
      case ProviderEventType.contextChanged:
        record.status = ProviderStatus.ready;
        record.latestStateEvent = event;
        break;
      case ProviderEventType.error:
        record.status = event.errorCode == ErrorCode.providerFatal
            ? ProviderStatus.fatal
            : ProviderStatus.error;
        record.latestStateEvent = event;
        break;
      case ProviderEventType.stale:
        record.status = ProviderStatus.stale;
        record.latestStateEvent = event;
        break;
      case ProviderEventType.reconciling:
        record.status = ProviderStatus.reconciling;
        record.latestStateEvent = event;
        break;
      case ProviderEventType.configurationChanged:
        break;
    }
  }

  void _dispatchReconciliationEvent(
    FeatureProvider provider,
    _ReconciliationResult? reconciliation,
  ) {
    if (reconciliation == null) {
      return;
    }
    final record = reconciliation.record;
    if (record.quarantined || !identical(_providerRecords[provider], record)) {
      return;
    }
    _applyEventState(record, reconciliation.event);
    if (record.bindingCount == 0) {
      record.pendingBindingEvents.add(reconciliation.event);
    } else {
      _dispatchEvent(provider, record, reconciliation.event);
    }
  }

  ProviderEventSubscription _addHandler(
    ProviderEventType eventType,
    ProviderEventHandler handler, {
    required String? domain,
    required bool apiWide,
  }) {
    late final _EventHandlerRecord record;
    late final ProviderEventSubscription subscription;
    subscription = ProviderEventSubscription._(() {
      _eventHandlers.remove(record);
    });
    record = _EventHandlerRecord(
      eventType: eventType,
      handler: handler,
      domain: domain,
      apiWide: apiWide,
      subscription: subscription,
    );
    _eventHandlers.add(record);
    _dispatchCurrentState(record);
    return subscription;
  }

  void _dispatchCurrentState(_EventHandlerRecord handlerRecord) {
    if (handlerRecord.apiWide) {
      for (final entry in _providerRecords.entries) {
        if (entry.value.bindingCount > 0) {
          _dispatchCurrentStateForProvider(
            handlerRecord,
            entry.key,
            entry.value,
          );
        }
      }
      return;
    }

    final provider = _providerForDomain(handlerRecord.domain);
    final providerRecord = _providerRecords[provider];
    if (providerRecord != null) {
      _dispatchCurrentStateForProvider(handlerRecord, provider, providerRecord);
    }
  }

  void _dispatchCurrentStateForProvider(
    _EventHandlerRecord handlerRecord,
    FeatureProvider provider,
    _ProviderRecord providerRecord,
  ) {
    final eventType = switch (providerRecord.status) {
      ProviderStatus.ready => ProviderEventType.ready,
      ProviderStatus.reconciling => ProviderEventType.reconciling,
      ProviderStatus.stale => ProviderEventType.stale,
      ProviderStatus.error || ProviderStatus.fatal => ProviderEventType.error,
      ProviderStatus.notReady => null,
    };
    if (eventType != handlerRecord.eventType) {
      return;
    }
    final latestStateEvent = providerRecord.latestStateEvent;
    _invokeHandler(
      handlerRecord,
      providerRecord,
      ProviderEvent(
        type: eventType!,
        flagsChanged: latestStateEvent?.flagsChanged ?? const [],
        message: latestStateEvent?.message,
        errorCode: latestStateEvent?.errorCode,
        metadata: latestStateEvent?.metadata ?? const {},
      ),
    );
  }

  void _dispatchEvent(
    FeatureProvider provider,
    _ProviderRecord providerRecord,
    ProviderEvent event,
  ) {
    for (final handlerRecord in _eventHandlers.toList(growable: false)) {
      if (!handlerRecord.subscription.isActive ||
          handlerRecord.eventType != event.type) {
        continue;
      }
      final isAssociated =
          handlerRecord.apiWide ||
          identical(_providerForDomain(handlerRecord.domain), provider);
      if (isAssociated) {
        _invokeHandler(handlerRecord, providerRecord, event);
      }
    }
  }

  void _invokeHandler(
    _EventHandlerRecord handlerRecord,
    _ProviderRecord providerRecord,
    ProviderEvent event,
  ) {
    try {
      handlerRecord.handler(
        ProviderEventDetails(
          type: event.type,
          providerMetadata: providerRecord.metadata,
          domain: handlerRecord.apiWide
              ? providerRecord.initialDomain
              : handlerRecord.domain,
          flagsChanged: event.flagsChanged,
          message: event.message,
          errorCode: event.errorCode,
          metadata: event.metadata,
        ),
      );
    } on Object {
      // A failing event handler must not block lifecycle or other handlers.
    }
  }

  Future<void> _releaseProvider(FeatureProvider provider) async {
    final record = _providerRecords[provider];
    if (record == null) {
      return;
    }
    record.bindingCount--;
    if (record.bindingCount > 0) {
      return;
    }
    await _disposeProvider(provider, record);
  }

  void _markProviderQuarantined(
    FeatureProvider provider,
    _ProviderRecord record,
  ) {
    record.quarantined = true;
    _quarantinedProviders[provider] = true;
  }

  Future<void> _quarantineProvider(
    FeatureProvider provider,
    _ProviderRecord record,
  ) async {
    _markProviderQuarantined(provider, record);
    if (identical(_defaultProvider, provider)) {
      _defaultProvider = _noOpProvider;
    }
    _domainProviders.removeWhere((_, value) => identical(value, provider));
    record.bindingCount = 0;
    try {
      await _disposeProvider(provider, record);
    } on Object {
      // The lifecycle timeout remains the primary failure reported to callers.
    }
  }

  Future<void> _disposeProvider(
    FeatureProvider provider,
    _ProviderRecord record,
  ) async {
    Object? cleanupError;
    StackTrace? cleanupStackTrace;
    final cancellation = () async {
      try {
        await record.eventSubscription?.cancel();
      } on Object catch (error, stackTrace) {
        cleanupError = error;
        cleanupStackTrace = stackTrace;
      }
    }();

    final shutdown = () async {
      try {
        if (provider is ShutdownProvider) {
          await (provider as ShutdownProvider).shutdown();
        }
      } on Object catch (error, stackTrace) {
        cleanupError ??= error;
        cleanupStackTrace ??= stackTrace;
      }
    }();
    final cleanup = Future.wait([cancellation, shutdown]);
    var timedOut = false;
    try {
      await cleanup.timeout(
        lifecycleTimeout,
        onTimeout: () {
          timedOut = true;
          throw OpenFeatureException(
            'Provider cleanup did not complete within '
            '${lifecycleTimeout.inMilliseconds} ms.',
          );
        },
      );
    } on Object catch (error, stackTrace) {
      cleanupError ??= error;
      cleanupStackTrace ??= stackTrace;
      if (timedOut) {
        _markProviderQuarantined(provider, record);
      }
    } finally {
      record.eventSubscription = null;
      record.lifecycleOperation = null;
      record.pendingBindingEvents.clear();
      record.bindingCount = 0;
      record.status = ProviderStatus.notReady;
      _providerRecords.remove(provider);
      if (identical(_providerOwners[provider], this)) {
        _providerOwners.remove(provider);
      }
    }

    final error = cleanupError;
    if (error != null) {
      Error.throwWithStackTrace(error, cleanupStackTrace!);
    }
  }
}

/// A client bound to one OpenFeature domain.
final class OpenFeatureClient {
  OpenFeatureClient._(this._api, this.metadata);

  final OpenFeatureAPI _api;
  final List<Hook> _hooks = <Hook>[];

  final ClientMetadata metadata;

  ProviderMetadata get providerMetadata =>
      _api.getProviderMetadata(metadata.domain);

  ProviderStatus get providerStatus => _api._statusForDomain(metadata.domain);

  /// Adds client hooks without removing existing hooks.
  void addHooks(Iterable<Hook> hooks) => _hooks.addAll(hooks);

  /// Adds a handler for events associated with this client.
  ///
  /// The handler remains registered across provider changes.
  ProviderEventSubscription addHandler(
    ProviderEventType eventType,
    ProviderEventHandler handler,
  ) {
    return _api._addHandler(
      eventType,
      handler,
      domain: metadata.domain,
      apiWide: false,
    );
  }

  /// Removes a previously registered client event handler.
  void removeHandler(ProviderEventSubscription subscription) {
    subscription.cancel();
  }

  bool getBooleanValue(
    String flagKey,
    bool defaultValue, {
    EvaluationOptions? options,
  }) => getBooleanDetails(flagKey, defaultValue, options: options).value;

  FlagEvaluationDetails<bool> getBooleanDetails(
    String flagKey,
    bool defaultValue, {
    EvaluationOptions? options,
  }) {
    return _evaluate(
      flagKey,
      defaultValue,
      FlagValueType.boolean,
      (provider, context) =>
          provider.resolveBooleanValue(flagKey, defaultValue, context),
      options: options,
    );
  }

  String getStringValue(
    String flagKey,
    String defaultValue, {
    EvaluationOptions? options,
  }) => getStringDetails(flagKey, defaultValue, options: options).value;

  FlagEvaluationDetails<String> getStringDetails(
    String flagKey,
    String defaultValue, {
    EvaluationOptions? options,
  }) {
    return _evaluate(
      flagKey,
      defaultValue,
      FlagValueType.string,
      (provider, context) =>
          provider.resolveStringValue(flagKey, defaultValue, context),
      options: options,
    );
  }

  int getIntegerValue(
    String flagKey,
    int defaultValue, {
    EvaluationOptions? options,
  }) => getIntegerDetails(flagKey, defaultValue, options: options).value;

  FlagEvaluationDetails<int> getIntegerDetails(
    String flagKey,
    int defaultValue, {
    EvaluationOptions? options,
  }) {
    return _evaluate(
      flagKey,
      defaultValue,
      FlagValueType.integer,
      (provider, context) =>
          provider.resolveIntegerValue(flagKey, defaultValue, context),
      options: options,
    );
  }

  double getDoubleValue(
    String flagKey,
    double defaultValue, {
    EvaluationOptions? options,
  }) => getDoubleDetails(flagKey, defaultValue, options: options).value;

  FlagEvaluationDetails<double> getDoubleDetails(
    String flagKey,
    double defaultValue, {
    EvaluationOptions? options,
  }) {
    return _evaluate(
      flagKey,
      defaultValue,
      FlagValueType.double,
      (provider, context) =>
          provider.resolveDoubleValue(flagKey, defaultValue, context),
      options: options,
    );
  }

  Map<String, Object?> getStructureValue(
    String flagKey,
    Map<String, Object?> defaultValue, {
    EvaluationOptions? options,
  }) => getStructureDetails(flagKey, defaultValue, options: options).value;

  FlagEvaluationDetails<Map<String, Object?>> getStructureDetails(
    String flagKey,
    Map<String, Object?> defaultValue, {
    EvaluationOptions? options,
  }) {
    return _evaluate(
      flagKey,
      defaultValue,
      FlagValueType.structure,
      (provider, context) =>
          provider.resolveStructureValue(flagKey, defaultValue, context),
      options: options,
    );
  }

  /// Sends a non-blocking tracking call when the provider supports tracking.
  void track(String trackingEventName, {TrackingEventDetails? details}) {
    final provider = _api._providerForDomain(metadata.domain);
    if (provider is TrackingProvider) {
      try {
        (provider as TrackingProvider).track(
          trackingEventName,
          _api._contextForDomain(metadata.domain),
          details: details,
        );
      } on Object {
        // Tracking support must not cause abnormal application execution.
      }
    }
  }

  FlagEvaluationDetails<T> _evaluate<T extends Object>(
    String flagKey,
    T defaultValue,
    FlagValueType flagValueType,
    ResolutionDetails<T> Function(
      FeatureProvider provider,
      EvaluationContext context,
    )
    resolve, {
    EvaluationOptions? options,
  }) {
    final provider = _api._providerForDomain(metadata.domain);
    final evaluationContext = _api._contextForDomain(metadata.domain);
    final hints = options?.hookHints ?? HookHints();
    final hooks = <Hook>[..._api._hooks, ..._hooks, ...?options?.hooks];
    ProviderMetadata providerMetadata =
        _api._providerRecords[provider]?.metadata ??
        const ProviderMetadata(name: 'unknown');
    Object? setupError;
    try {
      providerMetadata = provider.metadata;
      if (provider is ProviderHooks) {
        hooks.addAll((provider as ProviderHooks).hooks);
      }
    } on Object catch (error) {
      setupError = error;
    }

    final hookContexts = hooks
        .map(
          (_) => HookContext(
            flagKey: flagKey,
            defaultValue: defaultValue,
            flagValueType: flagValueType,
            clientMetadata: metadata,
            providerMetadata: providerMetadata,
            evaluationContext: evaluationContext,
          ),
        )
        .toList(growable: false);

    FlagEvaluationDetails<T>? details;
    Object? evaluationError = setupError;
    try {
      if (setupError == null) {
        for (var index = 0; index < hooks.length; index++) {
          hooks[index].before(hookContexts[index], hints);
        }
        final resolution = resolve(provider, evaluationContext);
        details = FlagEvaluationDetails<T>(
          flagKey: flagKey,
          value: resolution.errorCode == null ? resolution.value : defaultValue,
          errorCode: resolution.errorCode,
          errorMessage: resolution.errorMessage,
          reason: resolution.errorCode == null ? resolution.reason : 'ERROR',
          variant: resolution.variant,
          flagMetadata: resolution.flagMetadata,
        );
        if (resolution.errorCode != null) {
          evaluationError = OpenFeatureException(
            resolution.errorMessage ?? 'Provider resolution failed.',
            errorCode: resolution.errorCode!,
          );
        } else {
          for (var index = hooks.length - 1; index >= 0; index--) {
            hooks[index].after(hookContexts[index], details, hints);
          }
        }
      } else {
        details = _errorDetails(flagKey, defaultValue, setupError);
      }
    } on Object catch (error) {
      evaluationError = error;
      details = _errorDetails(flagKey, defaultValue, error);
    }

    if (evaluationError != null) {
      for (var index = hooks.length - 1; index >= 0; index--) {
        try {
          hooks[index].error(hookContexts[index], evaluationError, hints);
        } on Object {
          // Error hooks must not prevent remaining hooks or evaluation.
        }
      }
    }

    for (var index = hooks.length - 1; index >= 0; index--) {
      try {
        hooks[index].finallyAfter(hookContexts[index], details, hints);
      } on Object {
        // Finally hooks must not prevent remaining hooks or evaluation.
      }
    }
    return details;
  }

  FlagEvaluationDetails<T> _errorDetails<T extends Object>(
    String flagKey,
    T defaultValue,
    Object error,
  ) {
    return FlagEvaluationDetails<T>(
      flagKey: flagKey,
      value: defaultValue,
      errorCode: error is OpenFeatureException
          ? error.errorCode
          : ErrorCode.general,
      errorMessage: error.toString(),
      reason: 'ERROR',
    );
  }
}

/// Registration returned by API and client event-handler methods.
final class ProviderEventSubscription {
  ProviderEventSubscription._(this._cancelHandler);

  final void Function() _cancelHandler;
  bool _isActive = true;

  bool get isActive => _isActive;

  /// Stops future event delivery. Repeated calls have no effect.
  void cancel() {
    if (!_isActive) {
      return;
    }
    _isActive = false;
    _cancelHandler();
  }

  void _deactivate() => _isActive = false;
}

final class _EventHandlerRecord {
  const _EventHandlerRecord({
    required this.eventType,
    required this.handler,
    required this.domain,
    required this.apiWide,
    required this.subscription,
  });

  final ProviderEventType eventType;
  final ProviderEventHandler handler;
  final String? domain;
  final bool apiWide;
  final ProviderEventSubscription subscription;
}

final class _ProviderRecord {
  _ProviderRecord({
    required this.initialDomain,
    required this.metadata,
    required this.activeContext,
  });

  final String? initialDomain;
  final ProviderMetadata metadata;
  EvaluationContext activeContext;
  ProviderStatus status = ProviderStatus.notReady;
  int bindingCount = 0;
  StreamSubscription<ProviderEvent>? eventSubscription;
  _LifecycleOperation? lifecycleOperation;
  bool quarantined = false;
  ProviderEvent? latestStateEvent;
  final List<ProviderEvent> pendingBindingEvents = <ProviderEvent>[];
}

final class _ReconciliationResult {
  const _ReconciliationResult(this.record, this.event);

  final _ProviderRecord record;
  final ProviderEvent event;
}

final class _LifecycleOperation {
  _LifecycleOperation(this.successEventType);

  final ProviderEventType successEventType;
  final Completer<ProviderStatus> _terminal = Completer<ProviderStatus>();
  ProviderStatus? _latestStatus;
  ProviderEvent? _terminalEvent;
  bool _callbackCompleted = false;

  Future<ProviderStatus> get future => _terminal.future;
  ProviderEvent? get terminalEvent => _terminalEvent;

  void observe(ProviderEvent event, ProviderStatus status) {
    if (event.type != successEventType &&
        event.type != ProviderEventType.error) {
      return;
    }
    _latestStatus = status;
    _terminalEvent = event;
    _completeIfReady();
  }

  void completeCallback() {
    _callbackCompleted = true;
    _completeIfReady();
  }

  void _completeIfReady() {
    final status = _latestStatus;
    if (_callbackCompleted && status != null && !_terminal.isCompleted) {
      _terminal.complete(status);
    }
  }
}
