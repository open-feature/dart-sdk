import 'dart:async';
import 'dart:collection';

import '../feature_provider.dart';
import '../evaluation_context.dart';
import '../provider_capabilities.dart';
import 'provider_adapter.dart';
import '../provider_lifecycle.dart';

typedef ProviderLifecycleEventHandler =
    void Function(FeatureProvider provider, ProviderLifecycleEvent event);

/// Coordinates provider lifecycle by provider instance.
///
/// Providers implementing [ProviderEventSource] own their lifecycle events.
/// Providers without that capability are supported by a deprecated compatibility
/// path that derives ready/error events from lifecycle return values and state.
class ProviderLifecycleManager {
  static const Duration _lifecycleEventTimeout =
      LegacyProviderLifecycleAdapter.eventDeliveryGrace;

  final ProviderLifecycleEventHandler _onProviderEvent;
  final void Function(FeatureProvider)? _onRetired;
  final HashMap<FeatureProvider, _ProviderLifecycleRecord> _records =
      HashMap.identity();
  bool _disposed = false;
  Future<void>? _shutdownAllFuture;

  ProviderLifecycleManager(
    this._onProviderEvent, {
    void Function(FeatureProvider)? onRetired,
  }) : _onRetired = onRetired;

  Map<FeatureProvider, Future<void>> get pendingInitializations =>
      Map<FeatureProvider, Future<void>>.identity()..addEntries([
        for (final entry in _records.entries)
          if (entry.value.initialization != null)
            MapEntry(entry.key, entry.value.initialization!),
      ]);

  /// Detaches all records immediately and shuts down each lifecycle once.
  /// Provider shutdown must abort its own pending initialization (2.5.2).
  Future<void> shutdownAll() => _shutdownAllFuture ??= _shutdownAll();

  Future<void> _shutdownAll() async {
    _disposed = true;
    final records = _records.entries.toList();
    for (final entry in records) {
      final record = entry.value;
      record.defaultBinding = false;
      record.domains.clear();
      final signal = record.initializationSignal;
      if (signal != null && !signal.isCompleted) {
        signal.completeError(
          StateError('Provider initialization was canceled by shutdown.'),
        );
      }
    }
    // Start every cleanup even if another provider stalls or fails.
    await Future.wait(
      records.map((entry) => _shutdownAfterFinalUse(entry.key, entry.value)),
    );
  }

  _ProviderLifecycleRecord _recordFor(FeatureProvider provider) {
    if (_disposed) {
      throw StateError('ProviderLifecycleManager has been disposed.');
    }
    return _records.putIfAbsent(provider, () {
      if (provider is ResolverProviderAdapter) provider.beginLifecycle();
      final record = _ProviderLifecycleRecord(
        status: _normalizeState(provider.state),
        usesLegacyLifecycle: provider is! ProviderEventSource,
      );

      if (provider case final ProviderEventSource eventSource) {
        record.eventSubscription = eventSource.providerEvents.listen(
          (event) => _handleProviderEvent(provider, record, event),
        );
      }

      return record;
    });
  }

  ProviderState statusOf(FeatureProvider provider) =>
      _disposed ? ProviderState.NOT_READY : _recordFor(provider).status;

  /// Reads tracked state without reviving a retired provider or subscribing.
  ProviderState? trackedStatusOf(FeatureProvider provider) =>
      _disposed ? null : _records[provider]?.status;

  bool usesLegacyLifecycle(FeatureProvider provider) =>
      _recordFor(provider).usesLegacyLifecycle;

  /// Starts lifecycle tracking without relying on a status lookup for its
  /// side effect.
  void track(FeatureProvider provider) {
    _recordFor(provider);
  }

  void bindDefault(FeatureProvider provider) {
    _recordFor(provider).defaultBinding = true;
  }

  void bindDomain(FeatureProvider provider, String domain) {
    final record = _recordFor(provider);
    if (provider is DomainScopedProvider &&
        record.domains.isNotEmpty &&
        !record.domains.contains(domain)) {
      throw ProviderException(
        'Domain-scoped provider ${provider.metadata.name} is already bound to '
        '${record.domains.first}.',
        code: ErrorCode.INVALID_CONTEXT,
        details: {'domain': domain, 'boundDomains': record.domains.toList()},
      );
    }
    record.domains.add(domain);
  }

  Future<void> unbindDefault(FeatureProvider provider) async {
    final record = _records[provider];
    if (record == null) {
      return;
    }
    record.defaultBinding = false;
    await _shutdownAfterFinalUse(provider, record);
  }

  Future<void> unbindDomain(FeatureProvider provider, String domain) async {
    final record = _records[provider];
    if (record == null) {
      return;
    }
    record.domains.remove(domain);
    await _shutdownAfterFinalUse(provider, record);
  }

  /// Shuts down a tracked provider when it has no active bindings.
  Future<void> shutdownIfUnused(
    FeatureProvider provider, {
    bool Function()? isExternallyInUse,
  }) async {
    final record = _records[provider];
    if (record == null || (isExternallyInUse?.call() ?? false)) {
      return;
    }
    final activeInitialization = record.initialization;
    if (activeInitialization != null) {
      try {
        await activeInitialization;
      } catch (_) {
        // Failed initialization does not make an unbound provider live.
      }
      if (!identical(_records[provider], record)) {
        return;
      }
    }
    if (isExternallyInUse?.call() ?? false) {
      return;
    }
    await _shutdownAfterFinalUse(provider, record);
  }

  Future<void> initialize(
    FeatureProvider provider, {
    EvaluationContext? context,
    String? domain,
  }) {
    final record = _recordFor(provider);
    final activeShutdown = record.shutdown;
    if (activeShutdown != null) {
      // A provider cannot be initialized safely until its prior binding has
      // finished shutting down and its lifecycle record has been discarded.
      return _initializeAfterShutdown(
        provider,
        activeShutdown,
        context?.snapshot(),
        domain,
      );
    }

    if (provider is ResolverProviderAdapter &&
        !provider.requiresInitialization) {
      // 2.8.5: resolver-only providers are ready without initialization events.
      if (!record.lifecycleObserved && record.status == ProviderState.READY) {
        record.lifecycleObserved = true;
        _onProviderEvent(
          provider,
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_READY,
            'Provider ready without initialization: ${provider.metadata.name}',
          ),
        );
      }
      return Future.value();
    }

    if (provider is ProviderInitialization) {
      if (provider is DomainScopedProvider &&
          record.initializationDomainSet &&
          record.initializationDomain != domain) {
        return Future.error(
          const ProviderException(
            'A domain-scoped provider cannot initialize for another domain.',
            code: ErrorCode.INVALID_CONTEXT,
          ),
        );
      }
      if (!record.initializationDomainSet) {
        record.initializationDomainSet = true;
        record.initializationDomain = domain;
      }
    }

    if (record.status == ProviderState.READY &&
        (!record.usesLegacyLifecycle || record.lifecycleObserved)) {
      return Future.value();
    }

    final activeInitialization = record.initialization;
    if (activeInitialization != null) {
      return activeInitialization;
    }

    final initialization = record.usesLegacyLifecycle
        ? _initializeLegacyProvider(provider, record)
        : _initializeEventProvider(
            provider,
            record,
            context?.snapshot() ?? EvaluationContext.immutable(),
            domain,
          );
    record.initialization = initialization;
    return initialization.whenComplete(() {
      record.initialization = null;
    });
  }

  Future<void> _initializeAfterShutdown(
    FeatureProvider provider,
    Future<void> activeShutdown,
    EvaluationContext? context,
    String? domain,
  ) async {
    try {
      await activeShutdown;
    } catch (_) {
      // A failed shutdown still retires the old lifecycle record. Rebinding
      // must create and initialize a fresh record instead of inheriting the
      // prior shutdown failure.
    }
    _recordFor(provider).status = ProviderState.NOT_READY;
    await initialize(provider, context: context, domain: domain);
  }

  Future<void> _initializeLegacyProvider(
    FeatureProvider provider,
    _ProviderLifecycleRecord record,
  ) async {
    var errorEventEmitted = false;
    try {
      if (record.status == ProviderState.NOT_READY) {
        await LegacyProviderLifecycleAdapter.initialize(provider);
      }

      if (_disposed)
        throw StateError('Provider initialization was canceled by shutdown.');

      final observedStatus = _normalizeState(provider.state);
      record.status = observedStatus;
      if (observedStatus == ProviderState.READY) {
        _onProviderEvent(
          provider,
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_READY,
            'Provider ready: ${provider.name}',
          ),
        );
        record.lifecycleObserved = true;
        return;
      }

      final errorCode = _errorCodeForState(observedStatus);
      record.status = errorCode == ErrorCode.PROVIDER_FATAL
          ? ProviderState.FATAL
          : ProviderState.ERROR;
      _onProviderEvent(
        provider,
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_ERROR,
          'Provider not ready: ${provider.name}',
          data: {'state': observedStatus.name, 'legacyLifecycle': true},
          errorCode: errorCode,
        ),
      );
      record.lifecycleObserved = true;
      errorEventEmitted = true;
      throw ProviderException(
        'Provider failed to reach READY state: ${observedStatus.name}',
        code: errorCode ?? ErrorCode.PROVIDER_NOT_READY,
      );
    } catch (error) {
      if (_disposed) rethrow;
      if (!errorEventEmitted) {
        record.status = _statusForError(error, provider.state);
        _onProviderEvent(
          provider,
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_ERROR,
            'Provider initialization failed: ${provider.name}',
            data: {'error': error, 'legacyLifecycle': true},
            errorCode: _errorCodeForError(error, record.status),
          ),
        );
        record.lifecycleObserved = true;
      }
      rethrow;
    }
  }

  Future<void> _initializeEventProvider(
    FeatureProvider provider,
    _ProviderLifecycleRecord record,
    EvaluationContext context,
    String? domain,
  ) async {
    if (record.status != ProviderState.NOT_READY) {
      throw ProviderException(
        'Provider is not ready for initialization: ${record.status.name}',
        code: _errorCodeForState(record.status) ?? ErrorCode.PROVIDER_NOT_READY,
      );
    }

    final signal = Completer<ProviderLifecycleEvent>();
    // Shutdown may cancel the signal while provider initialization is awaited.
    // Observe early cancellation without consuming its eventual awaited error.
    signal.future.ignore();
    record.initializationSignal = signal;

    Object? initializationError;
    StackTrace? initializationStack;
    try {
      if (provider case final ProviderInitialization initialization) {
        await initialization.initializeProvider(context, domain: domain);
      } else {
        await LegacyProviderLifecycleAdapter.initialize(provider);
      }
    } catch (error, stackTrace) {
      initializationError = error;
      initializationStack = stackTrace;
    }

    ProviderLifecycleEvent event;
    if (_disposed)
      throw StateError('Provider initialization was canceled by shutdown.');
    try {
      if (provider is ProviderInitialization && !signal.isCompleted) {
        record.strictInitializationFailed = true;
        record.status = _statusForError(
          initializationError ?? StateError('Missing initialization event'),
          ProviderState.ERROR,
        );
        throw ProviderException(
          'Provider ${provider.metadata.name} must emit its lifecycle event '
          'before initializeProvider terminates.',
          code: ErrorCode.GENERAL,
        );
      }
      event = await signal.future.timeout(_lifecycleEventTimeout);
    } on TimeoutException {
      Error.throwWithStackTrace(
        ProviderException(
          'Provider ${provider.metadata.name} did not emit a lifecycle event '
          'within ${_lifecycleEventTimeout.inMilliseconds}ms of '
          'initialization.',
          code: ErrorCode.GENERAL,
          details: {
            'expected': initializationError == null
                ? ProviderLifecycleEventType.PROVIDER_READY.name
                : ProviderLifecycleEventType.PROVIDER_ERROR.name,
            if (initializationError != null)
              'initializationError': initializationError,
          },
        ),
        initializationStack ?? StackTrace.current,
      );
    } finally {
      if (identical(record.initializationSignal, signal)) {
        record.initializationSignal = null;
      }
    }
    if (initializationError != null) {
      if (event.type != ProviderLifecycleEventType.PROVIDER_ERROR) {
        if (provider is ProviderInitialization) {
          record.strictInitializationFailed = true;
          record.status = _statusForError(
            initializationError,
            ProviderState.ERROR,
          );
        }
        throw ProviderException(
          'Provider ${provider.metadata.name} emitted ${event.type.name} after '
          'initialization failed.',
          code: ErrorCode.GENERAL,
        );
      }
      Error.throwWithStackTrace(
        initializationError,
        initializationStack ?? StackTrace.current,
      );
    }

    if (event.type != ProviderLifecycleEventType.PROVIDER_READY ||
        record.status != ProviderState.READY) {
      throw ProviderException(
        event.message,
        code:
            event.errorCode ??
            _errorCodeForState(record.status) ??
            ErrorCode.PROVIDER_NOT_READY,
        details: event.data is Map<String, dynamic>
            ? event.data as Map<String, dynamic>
            : null,
      );
    }
  }

  void _handleProviderEvent(
    FeatureProvider provider,
    _ProviderLifecycleRecord record,
    ProviderLifecycleEvent event,
  ) {
    if (_disposed ||
        !identical(_records[provider], record) ||
        record.strictInitializationFailed) {
      return;
    }
    record.status = _statusForEvent(event, record.status);
    record.lifecycleObserved = true;
    final signal = record.initializationSignal;
    if (signal != null &&
        !signal.isCompleted &&
        (event.type == ProviderLifecycleEventType.PROVIDER_READY ||
            event.type == ProviderLifecycleEventType.PROVIDER_ERROR)) {
      signal.complete(event);
    }

    // Status is updated before the API dispatches the event to handlers.
    _onProviderEvent(provider, event);
  }

  Future<void> _shutdownAfterFinalUse(
    FeatureProvider provider,
    _ProviderLifecycleRecord record,
  ) async {
    if (record.defaultBinding || record.domains.isNotEmpty) {
      return;
    }

    final activeShutdown = record.shutdown;
    if (activeShutdown != null) {
      return activeShutdown;
    }

    final shutdown = _shutdownProvider(provider, record);
    record.shutdown = shutdown;
    await shutdown.whenComplete(() {
      record.shutdown = null;
    });
  }

  Future<void> _shutdownProvider(
    FeatureProvider provider,
    _ProviderLifecycleRecord record,
  ) async {
    Object? firstError;
    StackTrace? firstStack;
    try {
      if (provider case final ProviderShutdown shutdown) {
        await shutdown.shutdownProvider();
      } else {
        await LegacyProviderLifecycleAdapter.shutdown(provider);
      }
    } catch (error, stackTrace) {
      firstError = error;
      firstStack = stackTrace;
    } finally {
      // Shutdown is the one lifecycle transition inferred by the SDK in v0.9,
      // regardless of whether the provider's shutdown future succeeds.
      record.status = ProviderState.NOT_READY;
      try {
        await record.eventSubscription?.cancel();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
      record.eventSubscription = null;
      record.lifecycleObserved = false;
      if (identical(_records[provider], record)) {
        _records.remove(provider);
        _onRetired?.call(provider);
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    Object? firstError;
    StackTrace? firstStack;
    for (final record in _records.values.toList()) {
      final signal = record.initializationSignal;
      if (signal != null && !signal.isCompleted) {
        signal.completeError(
          StateError('Provider lifecycle manager was disposed.'),
          StackTrace.current,
        );
      }
      try {
        await record.eventSubscription?.cancel();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
      record.eventSubscription = null;
    }
    _records.clear();
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack ?? StackTrace.current);
    }
  }

  static ProviderState _normalizeState(ProviderState state) {
    return switch (state) {
      ProviderState.SHUTDOWN => ProviderState.NOT_READY,
      ProviderState.PLUGIN_ERROR => ProviderState.ERROR,
      _ => state,
    };
  }

  static ProviderState _statusForEvent(
    ProviderLifecycleEvent event,
    ProviderState currentStatus,
  ) {
    return switch (event.type) {
      ProviderLifecycleEventType.PROVIDER_READY => ProviderState.READY,
      ProviderLifecycleEventType.PROVIDER_ERROR =>
        event.errorCode == ErrorCode.PROVIDER_FATAL
            ? ProviderState.FATAL
            : ProviderState.ERROR,
      ProviderLifecycleEventType.PROVIDER_STALE => ProviderState.STALE,
      ProviderLifecycleEventType.PROVIDER_CONTEXT_CHANGED =>
        ProviderState.READY,
      ProviderLifecycleEventType.PROVIDER_RECONCILING =>
        ProviderState.SYNCHRONIZING,
      ProviderLifecycleEventType.PROVIDER_CONFIGURATION_CHANGED =>
        currentStatus,
    };
  }

  static ProviderState _statusForError(Object error, ProviderState state) {
    if (error is ProviderException && error.code == ErrorCode.PROVIDER_FATAL) {
      return ProviderState.FATAL;
    }
    final normalized = _normalizeState(state);
    return normalized == ProviderState.FATAL
        ? ProviderState.FATAL
        : ProviderState.ERROR;
  }

  static ErrorCode? _errorCodeForState(ProviderState state) {
    return switch (state) {
      ProviderState.FATAL => ErrorCode.PROVIDER_FATAL,
      ProviderState.READY => null,
      _ => ErrorCode.PROVIDER_NOT_READY,
    };
  }

  static ErrorCode _errorCodeForError(Object error, ProviderState state) {
    if (error is ProviderException) {
      return error.code;
    }
    return _errorCodeForState(state) ?? ErrorCode.GENERAL;
  }
}

class _ProviderLifecycleRecord {
  ProviderState status;
  final bool usesLegacyLifecycle;
  bool lifecycleObserved = false;
  bool strictInitializationFailed = false;
  bool initializationDomainSet = false;
  String? initializationDomain;
  bool defaultBinding = false;
  final Set<String> domains = {};
  StreamSubscription<ProviderLifecycleEvent>? eventSubscription;
  Completer<ProviderLifecycleEvent>? initializationSignal;
  Future<void>? initialization;
  Future<void>? shutdown;

  _ProviderLifecycleRecord({
    required this.status,
    required this.usesLegacyLifecycle,
  });
}
