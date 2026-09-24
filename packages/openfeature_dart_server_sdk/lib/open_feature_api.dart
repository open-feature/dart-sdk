import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'client.dart';
import 'domain.dart';
import 'domain_manager.dart';
import 'evaluation_context.dart';
import 'feature_provider.dart';
import 'hooks.dart';
import 'open_feature_event.dart';
import 'provider_lifecycle.dart';
import 'src/provider_adapter.dart';
import 'src/provider_lifecycle_manager.dart';

/// Compatibility adapter for the legacy positional-map API.
/// New code can use [EvaluationContext.immutable] and
/// [OpenFeatureAPI.setEvaluationContext] directly.
class OpenFeatureEvaluationContext {
  final EvaluationContext _context;
  String? get targetingKey => _context.targetingKey;
  // Merges involving legacy contexts can retain a mutable backing map.
  Map<String, dynamic> get attributes =>
      UnmodifiableMapView(_context.attributes);

  OpenFeatureEvaluationContext(
    Map<String, dynamic> attributes, {
    String? targetingKey,
  }) : _context = EvaluationContext(
         attributes: Map<String, dynamic>.unmodifiable(attributes),
         targetingKey: targetingKey,
       );

  OpenFeatureEvaluationContext._(this._context);

  OpenFeatureEvaluationContext merge(OpenFeatureEvaluationContext other) {
    final merged = _context.merge(other._context);
    return OpenFeatureEvaluationContext._(merged);
  }

  EvaluationContext toEvaluationContext() => _context;
}

abstract class OpenFeatureHook {
  void beforeEvaluation(String flagKey, Map<String, dynamic>? context);
  void afterEvaluation(
    String flagKey,
    dynamic result,
    Map<String, dynamic>? context,
  );
}

/// Default provider that's immediately ready - completely independent
class _ImmediateReadyProvider implements FeatureProvider {
  @override
  String get name => 'InMemoryProvider';

  @override
  ProviderState get state => ProviderState.READY;

  @override
  ProviderConfig get config => const ProviderConfig();

  @override
  ProviderMetadata get metadata =>
      const ProviderMetadata(name: 'InMemoryProvider');

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {}

  @override
  Future<void> connect() async {}

  @override
  Future<void> shutdown() async {}

  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {}

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      ErrorCode.FLAG_NOT_FOUND,
      'Flag not found',
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      ErrorCode.FLAG_NOT_FOUND,
      'Flag not found',
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      ErrorCode.FLAG_NOT_FOUND,
      'Flag not found',
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      ErrorCode.FLAG_NOT_FOUND,
      'Flag not found',
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    return FlagEvaluationResult.error(
      flagKey,
      defaultValue,
      ErrorCode.FLAG_NOT_FOUND,
      'Flag not found',
      evaluatorId: name,
    );
  }
}

class OpenFeatureAPI {
  static final Logger _logger = Logger('OpenFeatureAPI');
  static OpenFeatureAPI? _instance;

  final _providerAdapters = Expando<FeatureProvider>('provider adapters');
  FeatureProvider _adaptProvider(Provider provider) {
    if (provider is FeatureProvider) return provider;
    return _providerAdapters[provider] ??= ResolverProviderAdapter(provider);
  }

  late FeatureProvider _provider;
  final Map<String, FeatureProvider> _providerRegistry = {};
  final Map<String, FeatureProvider> _domainProviderBindings = {};
  final Map<String, String> _domainProviderIds = {};
  final Map<String, int> _domainBindingGenerations = {};
  final DomainManager _domainManager = DomainManager();
  late final ProviderLifecycleManager _lifecycleManager;
  final List<OpenFeatureHook> _hooks = [];
  final List<Hook> _evaluationHooks = [];
  OpenFeatureEvaluationContext? _globalContext;
  StreamSubscription<Domain>? _domainSubscription;
  StreamSubscription<LogRecord>? _logSubscription;
  int _defaultBindingGeneration = 0;
  FeatureProvider? _requestedDefaultProvider;
  bool _disposed = false;

  final StreamController<FeatureProvider> _providerStreamController;
  final StreamController<OpenFeatureEvent> _eventStreamController;
  final StreamController<Map<String, String>> _domainUpdatesController;
  Future<void>? _disposeFuture;

  OpenFeatureAPI._internal()
    : _providerStreamController = StreamController<FeatureProvider>.broadcast(),
      _eventStreamController = StreamController<OpenFeatureEvent>.broadcast(),
      _domainUpdatesController =
          StreamController<Map<String, String>>.broadcast() {
    _configureLogging();
    _lifecycleManager = ProviderLifecycleManager(_handleProviderLifecycleEvent);
    _domainSubscription = _domainManager.domainUpdates.listen((domain) {
      if (!_disposed) {
        _domainUpdatesController.add({
          'clientId': domain.clientId,
          'providerName': domain.providerName,
        });
      }
    });
    final defaultProvider = _ImmediateReadyProvider();
    _defaultBindingGeneration++;
    _requestedDefaultProvider = defaultProvider;
    _installDefaultProvider(defaultProvider);
  }

  factory OpenFeatureAPI() {
    _instance ??= OpenFeatureAPI._internal();
    return _instance!;
  }

  void _configureLogging() {
    Logger.root.level = Level.ALL;
    _logSubscription = Logger.root.onRecord.listen((record) {
      print(
        '${record.time} [${record.level.name}] ${record.loggerName}: ${record.message}',
      );
    });
  }

  ErrorCode? _errorCodeFrom(Object? error, {ProviderState? state}) {
    if (error is ProviderException) {
      return error.code;
    }

    switch (state) {
      case ProviderState.FATAL:
        return ErrorCode.PROVIDER_FATAL;
      case ProviderState.NOT_READY:
      case ProviderState.CONNECTING:
      case ProviderState.RECONNECTING:
      case ProviderState.SHUTDOWN:
        return ErrorCode.PROVIDER_NOT_READY;
      default:
        return null;
    }
  }

  void _installDefaultProvider(FeatureProvider provider) {
    _provider = provider;
    _providerRegistry[_provider.metadata.name] = _provider;
    _lifecycleManager.bindDefault(_provider);
    _logger.info('Default provider initialized and ready');
    _emitEvent(
      OpenFeatureEventType.PROVIDER_READY,
      'Default provider ready',
      provider: _provider,
      providerMetadata: _provider.metadata,
    );
  }

  Future<void> setProvider(Provider definition) async {
    final provider = _adaptProvider(definition);
    _logger.info('Setting provider: ${provider.name}');
    await _setDefaultProvider(provider, rethrowInitializationError: false);
  }

  /// Set provider and wait for it to be ready
  Future<void> setProviderAndWait(Provider definition) async {
    final provider = _adaptProvider(definition);
    _logger.info('Setting provider and waiting: ${provider.name}');
    await _setDefaultProvider(provider, rethrowInitializationError: true);
  }

  Future<void> _setDefaultProvider(
    FeatureProvider provider, {
    required bool rethrowInitializationError,
  }) async {
    final requestGeneration = ++_defaultBindingGeneration;
    _requestedDefaultProvider = provider;
    Object? initializationError;
    StackTrace? initializationStack;

    try {
      await _lifecycleManager.initialize(provider, context: evaluationContext);
    } catch (error, stackTrace) {
      initializationError = error;
      initializationStack = stackTrace;
      _logger.severe('Failed to initialize provider: $error');
    }

    if (_disposed) {
      if (initializationError != null && rethrowInitializationError) {
        Error.throwWithStackTrace(
          initializationError,
          initializationStack ?? StackTrace.current,
        );
      }
      return;
    }

    if (requestGeneration != _defaultBindingGeneration) {
      if (!identical(_provider, provider)) {
        try {
          await _lifecycleManager.shutdownIfUnused(
            provider,
            isExternallyInUse: () =>
                identical(_requestedDefaultProvider, provider) ||
                _providerRegistry.values.any(
                  (registered) => identical(registered, provider),
                ),
          );
        } catch (error) {
          _logger.severe(
            'Failed to shutdown superseded provider '
            '${provider.metadata.name}: $error',
          );
        }
      }
      if (initializationError != null && rethrowInitializationError) {
        Error.throwWithStackTrace(
          initializationError,
          initializationStack ?? StackTrace.current,
        );
      }
      return;
    }

    final previousProvider = _provider;
    if (!identical(previousProvider, provider)) {
      _lifecycleManager.bindDefault(provider);
      _provider = provider;
      final registeredProvider = _providerRegistry[provider.metadata.name];
      if (registeredProvider == null ||
          identical(registeredProvider, previousProvider)) {
        _providerRegistry[provider.metadata.name] = provider;
        _activatePendingBindings(provider.metadata.name, provider);
      }
      _providerStreamController.add(provider);
      try {
        await _lifecycleManager.unbindDefault(previousProvider);
      } catch (error) {
        _logger.severe(
          'Failed to shutdown replaced provider '
          '${previousProvider.metadata.name}: $error',
        );
        _emitEvent(
          OpenFeatureEventType.PROVIDER_ERROR,
          'Replaced provider shutdown failed: ${previousProvider.name}',
          data: error,
          provider: previousProvider,
          providerMetadata: previousProvider.metadata,
          errorCode: _errorCodeFrom(error),
        );
      }
    }

    if (initializationError != null && rethrowInitializationError) {
      Error.throwWithStackTrace(
        initializationError,
        initializationStack ?? StackTrace.current,
      );
    }
  }

  /// Register a provider under an SDK identifier.
  ///
  /// The identifier defaults to provider metadata for backwards compatibility.
  /// Callers registering same-name instances must supply distinct identifiers.
  String registerProvider(Provider definition, {String? providerId}) {
    final provider = _adaptProvider(definition);
    final id = providerId ?? provider.metadata.name;
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'providerId', 'must not be empty');
    }
    _lifecycleManager.track(provider);
    final replacedProvider = _providerRegistry[id];
    _providerRegistry[id] = provider;
    _activatePendingBindings(id, provider);
    if (replacedProvider != null && !identical(replacedProvider, provider)) {
      unawaited(
        _lifecycleManager
            .shutdownIfUnused(
              replacedProvider,
              isExternallyInUse: () => _providerRegistry.values.any(
                (registered) => identical(registered, replacedProvider),
              ),
            )
            .catchError((Object error) {
              _logger.severe(
                'Failed to retire replaced provider registration $id: $error',
              );
            }),
      );
    }
    return id;
  }

  void _activatePendingBindings(String providerId, FeatureProvider provider) {
    final pendingDomains = _domainProviderIds.entries
        .where(
          (entry) =>
              entry.value == providerId &&
              !identical(_domainProviderBindings[entry.key], provider),
        )
        .map((entry) => entry.key)
        .toList();

    if (pendingDomains.isNotEmpty) {
      unawaited(
        _initializeAndBindDomainProvider(
          pendingDomains,
          providerId,
          provider,
        ).catchError((Object error) {
          _logger.severe('Failed to activate provider $providerId: $error');
        }),
      );
    }
  }

  Future<String> registerProviderAndWait(
    Provider definition, {
    String? providerId,
  }) async {
    final provider = _adaptProvider(definition);
    final id = registerProvider(provider, providerId: providerId);
    await _lifecycleManager.initialize(provider, context: evaluationContext);
    return id;
  }

  /// Shutdown the current provider after its final binding is removed.
  Future<void> shutdownProvider() async {
    _logger.info('Shutting down provider: ${_provider.name}');
    final provider = _provider;
    final replacement = _ImmediateReadyProvider();
    final requestGeneration = ++_defaultBindingGeneration;
    _requestedDefaultProvider = replacement;

    try {
      await _lifecycleManager.unbindDefault(provider);
    } catch (e) {
      _logger.severe('Error during provider shutdown: $e');
      _emitEvent(
        OpenFeatureEventType.PROVIDER_ERROR,
        'Provider shutdown failed: ${provider.name}',
        data: e,
        provider: provider,
        providerMetadata: provider.metadata,
        errorCode: _errorCodeFrom(e),
      );
    }

    if (requestGeneration == _defaultBindingGeneration) {
      _installDefaultProvider(replacement);
    }
  }

  FeatureProvider _resolveProviderForClient(String clientId, String? domain) {
    final bindingKey = domain ?? clientId;
    final directlyBoundProvider = _domainProviderBindings[bindingKey];
    if (directlyBoundProvider != null) {
      return directlyBoundProvider;
    }

    // A name-first or asynchronous binding is not active until provider
    // initialization and the direct binding both complete.
    if (_domainProviderIds.containsKey(bindingKey)) {
      return _provider;
    }

    final boundProviderName = _domainManager.getProviderForClient(bindingKey);
    if (boundProviderName == null) {
      return _provider;
    }

    return _providerRegistry[boundProviderName] ?? _provider;
  }

  /// Get or create a client
  FeatureClient getClient(String name, {String? domain}) {
    FeatureProvider resolveProvider() =>
        _resolveProviderForClient(name, domain);
    final selectedProvider = resolveProvider();
    EvaluationContext resolveApiContext() =>
        _globalContext?.toEvaluationContext() ??
        const EvaluationContext(attributes: {});

    final hookManager = HookManager();

    return FeatureClient(
      metadata: ClientMetadata(name: name, domain: domain ?? name),
      hookManager: hookManager,
      apiHooksResolver: () => List.unmodifiable(_evaluationHooks),
      apiContext: resolveApiContext(),
      apiContextResolver: resolveApiContext,
      defaultContext: const EvaluationContext(attributes: {}),
      provider: selectedProvider,
      providerResolver: resolveProvider,
      providerStatusResolver: _lifecycleManager.statusOf,
      eventStream: events,
    );
  }

  /// Wrap OpenFeatureHook into Hook interface
  Hook _wrapHook(OpenFeatureHook openFeatureHook) {
    return _OpenFeatureHookAdapter(openFeatureHook);
  }

  FeatureProvider get provider => _provider;

  ProviderState get providerStatus => _lifecycleManager.statusOf(_provider);

  /// Set global evaluation fields using the canonical context representation.
  /// Existing clients resolve the latest snapshot on their next evaluation.
  void setEvaluationContext(EvaluationContext context) {
    setGlobalContext(OpenFeatureEvaluationContext._(context.snapshot()));
  }

  EvaluationContext? get evaluationContext =>
      _globalContext?.toEvaluationContext();

  void setGlobalContext(OpenFeatureEvaluationContext context) {
    _logger.info('Setting global context');
    _globalContext = context;
    _emitEvent(
      OpenFeatureEventType.PROVIDER_CONTEXT_CHANGED,
      'Global context updated',
    );
  }

  OpenFeatureEvaluationContext? get globalContext => _globalContext;

  void addHooks(List<OpenFeatureHook> hooks) {
    _hooks.addAll(hooks);
    _evaluationHooks.addAll(hooks.map(_wrapHook));
  }

  /// Adds typed hooks at API scope, including for already-created clients.
  void addEvaluationHooks(Iterable<Hook> hooks) =>
      _evaluationHooks.addAll(hooks);

  List<OpenFeatureHook> get hooks => List.unmodifiable(_hooks);

  StreamSubscription<OpenFeatureEvent> addHandler(
    void Function(OpenFeatureEvent event) handler,
  ) => events.listen(handler);

  Future<void> removeHandler(StreamSubscription<OpenFeatureEvent> handler) =>
      handler.cancel();

  void bindClientToProvider(String clientId, String providerId) {
    final provider = _providerRegistry[providerId];
    final request = _recordDomainBindingRequest(clientId, providerId);
    if (provider == null) {
      // Preserve the legacy name-first binding flow. Once a provider is
      // registered under this identifier, clients resolve it dynamically.
      _domainManager.bindClientToProvider(clientId, providerId);
      _emitEvent(
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
        'Domain $clientId bound to pending provider $providerId',
        domain: clientId,
      );
      return;
    }

    unawaited(
      _initializeAndBindDomainProvider(
        [clientId],
        providerId,
        provider,
      ).catchError((Object error) {
        _rollbackDomainBindingRequest(request);
        _logger.severe('Failed to bind provider $providerId: $error');
      }),
    );
  }

  Future<void> bindClientToProviderAndWait(
    String clientId,
    String providerId,
  ) async {
    final provider = _providerRegistry[providerId];
    if (provider == null) {
      throw ArgumentError.value(providerId, 'providerId', 'is not registered');
    }

    final request = _recordDomainBindingRequest(clientId, providerId);
    try {
      await _initializeAndBindDomainProvider([clientId], providerId, provider);
    } catch (_) {
      _rollbackDomainBindingRequest(request);
      rethrow;
    }
  }

  Future<void> setProviderForDomainAndWait(
    String domain,
    Provider definition, {
    String? providerId,
  }) async {
    final provider = _adaptProvider(definition);
    final id = registerProvider(provider, providerId: providerId);
    final request = _recordDomainBindingRequest(domain, id);
    try {
      await _initializeAndBindDomainProvider([domain], id, provider);
    } catch (_) {
      _rollbackDomainBindingRequest(request);
      rethrow;
    }
  }

  _DomainBindingRequest _recordDomainBindingRequest(
    String domain,
    String providerId,
  ) {
    final hadPreviousProviderId = _domainProviderIds.containsKey(domain);
    final previousProviderId = _domainProviderIds[domain];
    _domainProviderIds[domain] = providerId;
    final generation = (_domainBindingGenerations[domain] ?? 0) + 1;
    _domainBindingGenerations[domain] = generation;
    return _DomainBindingRequest(
      domain: domain,
      providerId: providerId,
      generation: generation,
      hadPreviousProviderId: hadPreviousProviderId,
      previousProviderId: previousProviderId,
    );
  }

  void _rollbackDomainBindingRequest(_DomainBindingRequest request) {
    if (_domainProviderIds[request.domain] != request.providerId ||
        _domainBindingGenerations[request.domain] != request.generation) {
      return;
    }

    _domainBindingGenerations[request.domain] = request.generation + 1;
    if (request.hadPreviousProviderId) {
      _domainProviderIds[request.domain] = request.previousProviderId!;
    } else {
      _domainProviderIds.remove(request.domain);
    }
  }

  Future<void> _initializeAndBindDomainProvider(
    Iterable<String> domains,
    String providerId,
    FeatureProvider provider,
  ) async {
    final requestGenerations = <String, int>{
      for (final domain in domains)
        domain: _domainBindingGenerations[domain] ?? 0,
    };
    await _lifecycleManager.initialize(
      provider,
      context: evaluationContext,
      domain: requestGenerations.keys.firstOrNull,
    );
    for (final request in requestGenerations.entries) {
      await _bindDomainProvider(
        request.key,
        providerId,
        provider,
        request.value,
      );
    }
  }

  Future<void> _bindDomainProvider(
    String domain,
    String providerId,
    FeatureProvider provider,
    int requestGeneration,
  ) async {
    if (_domainProviderIds[domain] != providerId ||
        _domainBindingGenerations[domain] != requestGeneration ||
        !identical(_providerRegistry[providerId], provider)) {
      return;
    }

    final previousProvider = _domainProviderBindings[domain];
    _lifecycleManager.bindDomain(provider, domain);
    _domainProviderBindings[domain] = provider;
    _domainProviderIds[domain] = providerId;
    _domainManager.bindClientToProvider(domain, providerId);
    _emitEvent(
      OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      'Domain $domain bound to provider $providerId',
      provider: provider,
      domain: domain,
      providerMetadata: provider.metadata,
    );

    if (previousProvider != null && !identical(previousProvider, provider)) {
      try {
        await _lifecycleManager.unbindDomain(previousProvider, domain);
      } catch (error) {
        _logger.severe(
          'Failed to shutdown provider removed from $domain: $error',
        );
        _emitEvent(
          OpenFeatureEventType.PROVIDER_ERROR,
          'Provider shutdown failed after removal from $domain',
          data: error,
          provider: previousProvider,
          providerMetadata: previousProvider.metadata,
          domain: domain,
          errorCode: _errorCodeFrom(error),
        );
      }
    }
  }

  /// @deprecated Use getClient().getBooleanFlag() instead
  /// This method exists for backwards compatibility only
  @Deprecated('Use getClient().getBooleanFlag() instead')
  Future<bool> evaluateBooleanFlag(
    String flagKey,
    String clientId, {
    Map<String, dynamic>? context,
  }) async {
    final client = getClient(clientId);
    return await client.getBooleanFlag(
      flagKey,
      defaultValue: false,
      context: context != null ? EvaluationContext(attributes: context) : null,
    );
  }

  void _handleProviderLifecycleEvent(
    FeatureProvider provider,
    ProviderLifecycleEvent event,
  ) {
    if (_disposed) {
      return;
    }
    final eventType = switch (event.type) {
      ProviderLifecycleEventType.PROVIDER_READY =>
        OpenFeatureEventType.PROVIDER_READY,
      ProviderLifecycleEventType.PROVIDER_ERROR =>
        OpenFeatureEventType.PROVIDER_ERROR,
      ProviderLifecycleEventType.PROVIDER_CONFIGURATION_CHANGED =>
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
      ProviderLifecycleEventType.PROVIDER_STALE =>
        OpenFeatureEventType.PROVIDER_STALE,
      ProviderLifecycleEventType.PROVIDER_CONTEXT_CHANGED =>
        OpenFeatureEventType.PROVIDER_CONTEXT_CHANGED,
      ProviderLifecycleEventType.PROVIDER_RECONCILING =>
        OpenFeatureEventType.PROVIDER_RECONCILING,
    };

    _emitEvent(
      eventType,
      event.message,
      data: event.data,
      provider: provider,
      providerMetadata: provider.metadata,
      errorCode: event.errorCode,
      timestamp: event.timestamp,
    );
  }

  void _emitEvent(
    OpenFeatureEventType type,
    String message, {
    dynamic data,
    FeatureProvider? provider,
    ProviderMetadata? providerMetadata,
    String? domain,
    ErrorCode? errorCode,
    DateTime? timestamp,
  }) {
    if (_disposed) {
      return;
    }
    final event = OpenFeatureEvent(
      type,
      message,
      data: data,
      provider: provider,
      providerMetadata: providerMetadata,
      domain: domain,
      errorCode: errorCode,
      timestamp: timestamp,
    );
    _eventStreamController.add(event);
  }

  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    Object? firstError;
    StackTrace? firstStack;

    Future<void> attempt(FutureOr<void> Function() operation) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        firstError ??= error;
        firstStack ??= stackTrace;
      }
    }

    final domainSubscription = _domainSubscription;
    _domainSubscription = null;
    await attempt(() => domainSubscription?.cancel());
    final logSubscription = _logSubscription;
    _logSubscription = null;
    await attempt(() => logSubscription?.cancel());
    await attempt(_lifecycleManager.dispose);
    await attempt(_domainManager.dispose);
    await attempt(_providerStreamController.close);
    await attempt(_eventStreamController.close);
    await attempt(_domainUpdatesController.close);

    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStack ?? StackTrace.current);
    }
  }

  /// Disposes the current singleton before allowing a replacement instance.
  static Future<void> resetInstance() async {
    final instance = _instance;
    if (instance == null) {
      return;
    }

    try {
      await instance.dispose();
    } finally {
      if (identical(_instance, instance)) {
        _instance = null;
      }
    }
  }

  Stream<FeatureProvider> get providerUpdates =>
      _providerStreamController.stream;
  Stream<OpenFeatureEvent> get events => _eventStreamController.stream;
  Stream<Map<String, String>> get domainUpdates =>
      _domainUpdatesController.stream;
}

class _DomainBindingRequest {
  final String domain;
  final String providerId;
  final int generation;
  final bool hadPreviousProviderId;
  final String? previousProviderId;

  const _DomainBindingRequest({
    required this.domain,
    required this.providerId,
    required this.generation,
    required this.hadPreviousProviderId,
    required this.previousProviderId,
  });
}

class _OpenFeatureHookAdapter extends BaseHook {
  final OpenFeatureHook _hook;

  _OpenFeatureHookAdapter(this._hook)
    : super(metadata: HookMetadata(name: 'OpenFeatureHookAdapter'));

  @override
  Future<Map<String, dynamic>?> before(HookContext context) async {
    _hook.beforeEvaluation(context.flagKey, context.evaluationContext);
    return null;
  }

  @override
  Future<void> after(HookContext context) async {
    dynamic resultValue = context.result;
    if (resultValue is FlagEvaluationResult) {
      resultValue = resultValue.value;
    }
    _hook.afterEvaluation(
      context.flagKey,
      resultValue,
      context.evaluationContext,
    );
  }
}
