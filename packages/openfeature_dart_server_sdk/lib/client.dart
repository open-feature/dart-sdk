import 'dart:async';
import 'package:logging/logging.dart';
import 'evaluation_context.dart';
import 'feature_provider.dart';
import 'provider_capabilities.dart';
import 'src/provider_adapter.dart';
import 'hooks.dart';
import 'open_feature_event.dart';
import 'transaction_context.dart';
import 'src/context_snapshot.dart';

/// Client metadata for identification
class ClientMetadata {
  final String name;

  /// The requested binding domain, even when evaluation uses the default provider.
  final String domain;
  final String version;
  final Map<String, String> attributes;

  ClientMetadata({
    required this.name,
    String? domain,
    this.version = '1.0.0',
    Map<String, String> attributes = const {},
  }) : domain = domain ?? name,
       attributes = Map.unmodifiable(Map.of(attributes));
}

/// Client metrics for monitoring
class ClientMetrics {
  int flagEvaluations = 0;
  int trackingEvents = 0;
  List<Duration> responseTimes = [];
  Map<String, int> errorCounts = {};

  Duration get averageResponseTime {
    if (responseTimes.isEmpty) return Duration.zero;
    final total = responseTimes.fold<int>(
      0,
      (sum, duration) => sum + duration.inMilliseconds,
    );
    return Duration(milliseconds: total ~/ responseTimes.length);
  }

  Map<String, dynamic> toJson() => {
    'flagEvaluations': flagEvaluations,
    'trackingEvents': trackingEvents,
    'averageResponseTime': averageResponseTime.inMilliseconds,
    'errorCounts': errorCounts,
  };
}

/// Feature client - orchestrates evaluation without caching
class FeatureClient {
  final Logger _logger = Logger('FeatureClient');
  final ClientMetadata metadata;
  final HookManager _hookManager;
  final Iterable<Hook> Function()? _apiHooksResolver;
  final EvaluationContext _defaultContext;
  final EvaluationContext _apiContext;
  final EvaluationContext Function()? _apiContextResolver;
  final FeatureProvider _fallbackProvider;
  final FeatureProvider Function()? _providerResolver;
  final ProviderState Function(FeatureProvider)? _providerStatusResolver;
  final TransactionContextManager _transactionManager;
  final ClientMetrics _metrics = ClientMetrics();
  final StreamController<OpenFeatureEvent> _eventController =
      StreamController<OpenFeatureEvent>.broadcast();
  StreamSubscription<OpenFeatureEvent>? _eventSubscription;

  FeatureClient({
    required this.metadata,
    required HookManager hookManager,
    Iterable<Hook> Function()? apiHooksResolver,
    required EvaluationContext defaultContext,
    EvaluationContext? apiContext,
    EvaluationContext Function()? apiContextResolver,
    FeatureProvider? provider,
    FeatureProvider Function()? providerResolver,
    ProviderState Function(FeatureProvider)? providerStatusResolver,
    TransactionContextManager? transactionManager,
    Stream<OpenFeatureEvent>? eventStream,
  }) : _hookManager = hookManager,
       _apiHooksResolver = apiHooksResolver,
       _defaultContext = defaultContext,
       _apiContext = apiContext ?? const EvaluationContext(attributes: {}),
       _apiContextResolver = apiContextResolver,
       _fallbackProvider = provider ?? InMemoryProvider({}),
       _providerResolver = providerResolver,
       _providerStatusResolver = providerStatusResolver,
       _transactionManager = transactionManager ?? TransactionContextManager() {
    if (_providerResolver == null &&
        providerStatus == ProviderState.NOT_READY) {
      unawaited(
        this.provider.initialize().catchError((Object error, StackTrace stack) {
          _logger.severe(
            'Provider initialization failed: $error',
            error,
            stack,
          );
        }),
      );
    }

    if (eventStream != null) {
      _eventSubscription = eventStream.listen(_forwardEvent);
    }
  }

  void _forwardEvent(OpenFeatureEvent event) {
    final currentProvider = provider;
    if (event.provider != null) {
      if (identical(event.provider, currentProvider)) {
        _eventController.add(event);
      }
      return;
    }

    // Provider names are not unique. A dynamically bound client must not
    // infer an event's source from metadata when no provider identity exists.
    if (_providerResolver != null && event.providerMetadata != null) {
      return;
    }

    final eventProvider = event.providerMetadata?.name;
    if (eventProvider == null ||
        eventProvider == currentProvider.metadata.name) {
      _eventController.add(event);
    }
  }

  Stream<OpenFeatureEvent> get events => _eventController.stream;

  StreamSubscription<OpenFeatureEvent> addHandler(
    void Function(OpenFeatureEvent event) handler,
  ) => events.listen(handler);

  Future<void> removeHandler(StreamSubscription<OpenFeatureEvent> handler) =>
      handler.cancel();

  void addHook(Hook hook) {
    _hookManager.addHook(hook);
  }

  void addHooks(Iterable<Hook> hooks) {
    for (final hook in hooks) {
      _hookManager.addHook(hook);
    }
  }

  void removeHook(Hook hook) {
    _hookManager.removeHook(hook);
  }

  Map<String, dynamic> _buildEffectiveContext(EvaluationContext? context) {
    final apiContext = _apiContextResolver?.call() ?? _apiContext;
    return {
      ...apiContext.toProviderContext(),
      ..._transactionManager.currentContext?.effectiveAttributes ?? {},
      ..._defaultContext.toProviderContext(),
      ...context?.toProviderContext() ?? {},
    };
  }

  void _ensureProviderCanEvaluate(FeatureProvider evaluationProvider) {
    final state =
        _providerStatusResolver?.call(evaluationProvider) ??
        evaluationProvider.state;
    switch (state) {
      case ProviderState.NOT_READY:
      case ProviderState.SHUTDOWN:
        throw const ProviderException(
          'Provider is not ready.',
          code: ErrorCode.PROVIDER_NOT_READY,
        );
      case ProviderState.FATAL:
        throw const ProviderException(
          'Provider is in an irrecoverable error state.',
          code: ErrorCode.PROVIDER_FATAL,
        );
      default:
        return;
    }
  }

  FlagValueType _inferFlagValueType<T>(T defaultValue) {
    if (defaultValue is bool) return FlagValueType.BOOLEAN;
    if (defaultValue is String) return FlagValueType.STRING;
    if (defaultValue is int) return FlagValueType.INTEGER;
    if (defaultValue is double) return FlagValueType.DOUBLE;
    return FlagValueType.OBJECT;
  }

  EvaluationDetails _createEvaluationDetails<T>(
    FlagEvaluationResult<T> result,
  ) {
    return EvaluationDetails(
      flagKey: result.flagKey,
      value: result.value,
      variant: result.variant,
      reason: result.reason,
      evaluationTime: result.evaluatedAt,
      additionalDetails: result.details,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      flagMetadata: result.flagMetadata,
    );
  }

  Exception _asException(Object error) {
    return error is Exception ? error : Exception(_safeErrorMessage(error));
  }

  Exception _providerErrorAsException<T>(FlagEvaluationResult<T> result) {
    return ProviderException(
      result.errorMessage ?? 'Provider returned an evaluation error.',
      code: result.errorCode ?? ErrorCode.GENERAL,
      details: result.details,
    );
  }

  FlagEvaluationResult<T> _exceptionResult<T>(
    String flagKey,
    T defaultValue,
    Exception error,
    String evaluatorId,
  ) {
    final errorCode = error is ProviderException
        ? error.code
        : error is InvalidContextException
        ? ErrorCode.INVALID_CONTEXT
        : ErrorCode.GENERAL;
    final errorMessage = error is ProviderException
        ? error.message
        : _safeErrorMessage(error);

    return FlagEvaluationResult<T>(
      flagKey: flagKey,
      value: defaultValue,
      reason: 'ERROR',
      errorCode: errorCode,
      errorMessage: errorMessage,
      details: error is ProviderException ? error.details : null,
      evaluatedAt: DateTime.now(),
      evaluatorId: evaluatorId,
    );
  }

  void _recordEvaluationError(ErrorCode? errorCode, Exception error) {
    final errorKey = errorCode?.name ?? error.runtimeType.toString();
    _metrics.errorCounts[errorKey] = (_metrics.errorCounts[errorKey] ?? 0) + 1;
  }

  Future<FlagEvaluationResult<T>> _evaluateFlagResult<T>(
    String flagKey,
    T defaultValue,
    Future<FlagEvaluationResult<T>> Function(
      FeatureProvider,
      Map<String, dynamic>?,
    )
    evaluator, {
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async {
    final startTime = DateTime.now();
    var effectiveContext = <String, dynamic>{};
    final hookData = HookData();
    List<Hook> executionHooks = const [];
    final hints = options?.hints ?? const HookHints();
    ProviderMetadata? hookProviderMetadata;
    final flagValueType = _inferFlagValueType(defaultValue);
    FlagEvaluationResult<T>? finalResult;
    EvaluationDetails? evaluationDetails;
    Exception? evaluationError;
    _metrics.flagEvaluations++;

    try {
      executionHooks = List.unmodifiable([
        ...?_apiHooksResolver?.call(),
        ..._hookManager.registeredHooks,
        ...?options?.hooks,
      ]);
      effectiveContext = _buildEffectiveContext(context);
      final evaluationProvider = provider;
      executionHooks = List.unmodifiable([
        ...executionHooks,
        ...providerHooksFor(evaluationProvider),
      ]);
      final providerMetadata = evaluationProvider.metadata;
      hookProviderMetadata = ProviderMetadata(
        name: providerMetadata.name,
        version: providerMetadata.version,
        attributes: Map.unmodifiable(providerMetadata.attributes),
      );
      effectiveContext = await _hookManager.executeHooks(
        HookStage.BEFORE,
        flagKey,
        effectiveContext,
        clientMetadata: metadata,
        providerMetadata: hookProviderMetadata,
        defaultValue: defaultValue,
        flagValueType: flagValueType,
        hookData: hookData,
        executionHooks: executionHooks,
        hints: hints,
        onContextChanged: (updated) => effectiveContext = updated,
      );

      _ensureProviderCanEvaluate(evaluationProvider);
      finalResult = await evaluator(evaluationProvider, effectiveContext);
      // A provider may return an error together with a cached or otherwise
      // unusable value. Only the application chooses its fallback (1.4.10).
      if (finalResult.errorCode != null) {
        finalResult = FlagEvaluationResult<T>(
          flagKey: flagKey,
          value: defaultValue,
          reason: 'ERROR',
          errorCode: finalResult.errorCode,
          errorMessage: finalResult.errorMessage,
          flagMetadata: finalResult.flagMetadata,
          details: finalResult.details,
          evaluatedAt: finalResult.evaluatedAt,
          evaluatorId: finalResult.evaluatorId,
        );
      }
      evaluationDetails = _createEvaluationDetails(finalResult);

      if (finalResult.errorCode == null) {
        await _hookManager.executeHooks(
          HookStage.AFTER,
          flagKey,
          effectiveContext,
          result: finalResult.value,
          evaluationDetails: evaluationDetails,
          clientMetadata: metadata,
          providerMetadata: hookProviderMetadata,
          defaultValue: defaultValue,
          flagValueType: flagValueType,
          hookData: hookData,
          executionHooks: executionHooks,
          hints: hints,
        );
      } else {
        evaluationError = _providerErrorAsException(finalResult);
        _logger.warning(
          'Flag evaluation error for $flagKey: ${finalResult.errorMessage}',
        );
        _recordEvaluationError(finalResult.errorCode, evaluationError);

        await _hookManager.executeHooks(
          HookStage.ERROR,
          flagKey,
          effectiveContext,
          result: finalResult.value,
          error: evaluationError,
          evaluationDetails: evaluationDetails,
          clientMetadata: metadata,
          providerMetadata: hookProviderMetadata,
          defaultValue: defaultValue,
          flagValueType: flagValueType,
          hookData: hookData,
          executionHooks: executionHooks,
          hints: hints,
        );
      }
    } catch (e) {
      evaluationError = _asException(e);
      _logger.warning(
        'Error evaluating flag $flagKey: ${_safeErrorMessage(e)}',
      );
      if (finalResult == null || finalResult.errorCode == null) {
        finalResult = _exceptionResult(
          flagKey,
          defaultValue,
          evaluationError,
          hookProviderMetadata?.name ?? '',
        );
      }
      evaluationDetails = _createEvaluationDetails(finalResult);
      _recordEvaluationError(finalResult.errorCode, evaluationError);

      await _hookManager.executeHooks(
        HookStage.ERROR,
        flagKey,
        effectiveContext,
        result: finalResult.value,
        error: evaluationError,
        evaluationDetails: evaluationDetails,
        clientMetadata: metadata,
        providerMetadata: hookProviderMetadata,
        defaultValue: defaultValue,
        flagValueType: flagValueType,
        hookData: hookData,
        executionHooks: executionHooks,
        hints: hints,
      );
    } finally {
      _metrics.responseTimes.add(DateTime.now().difference(startTime));
      if (finalResult != null) {
        evaluationDetails ??= _createEvaluationDetails(finalResult);
      }
      await _hookManager.executeHooks(
        HookStage.FINALLY,
        flagKey,
        effectiveContext,
        result: finalResult?.value ?? defaultValue,
        error: evaluationError,
        evaluationDetails: evaluationDetails,
        clientMetadata: metadata,
        providerMetadata: hookProviderMetadata,
        defaultValue: defaultValue,
        flagValueType: flagValueType,
        hookData: hookData,
        executionHooks: executionHooks,
        hints: hints,
      );
    }

    return finalResult;
  }

  /// Generic flag evaluation orchestrator
  Future<T> _evaluateFlag<T>(
    String flagKey,
    T defaultValue,
    Future<FlagEvaluationResult<T>> Function(
      FeatureProvider,
      Map<String, dynamic>?,
    )
    evaluator, {
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      evaluator,
      context: context,
      options: options,
    );
    return result.value;
  }

  /// Evaluate boolean flag
  Future<bool> getBooleanFlag(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    bool defaultValue = false,
  }) {
    return _evaluateFlag(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) => evaluationProvider.getBooleanFlag(
        flagKey,
        defaultValue,
        context: ctx,
      ),
      context: context,
      options: options,
    );
  }

  /// Evaluate string flag
  Future<String> getStringFlag(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    String defaultValue = '',
  }) {
    return _evaluateFlag(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getStringFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );
  }

  /// Evaluate integer flag
  Future<int> getIntegerFlag(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    int defaultValue = 0,
  }) {
    return _evaluateFlag(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) => evaluationProvider.getIntegerFlag(
        flagKey,
        defaultValue,
        context: ctx,
      ),
      context: context,
      options: options,
    );
  }

  /// Evaluate double flag
  Future<double> getDoubleFlag(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    double defaultValue = 0.0,
  }) {
    return _evaluateFlag(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getDoubleFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );
  }

  Future<Map<String, dynamic>> getObjectFlag(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    Map<String, dynamic> defaultValue = const {},
  }) {
    return _evaluateFlag(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getObjectFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );
  }

  /// Tracking API (spec Section 6) - record a tracking event
  Future<void> track(
    String trackingEventName, {
    EvaluationContext? context,
    TrackingEventDetails? trackingDetails,
  }) async {
    _metrics.trackingEvents++;

    try {
      final effectiveContext = _buildEffectiveContext(context);
      final trackingProvider = provider;
      if (trackingProvider case final ProviderTracking tracking) {
        await tracking.trackEvent(
          trackingEventName,
          evaluationContext: effectiveContext,
          trackingDetails: trackingDetails,
        );
      } else {
        await trackingProvider.track(
          trackingEventName,
          evaluationContext: effectiveContext,
          trackingDetails: trackingDetails,
        );
      }
    } catch (e) {
      _logger.warning('Error sending tracking event "$trackingEventName": $e');
    }
  }

  ClientMetrics getMetrics() => _metrics;

  /// Access to provider for management operations
  FeatureProvider get provider =>
      _providerResolver?.call() ?? _fallbackProvider;

  /// Current status of the provider bound to this client.
  ProviderState get providerStatus =>
      _providerStatusResolver?.call(provider) ?? provider.state;

  Future<void> dispose() async {
    await _eventSubscription?.cancel();
    await _eventController.close();
  }
}

/// Evaluation methods for new consumers: application defaults are required.
///
/// The legacy get*Flag/get*Details methods remain source-compatible during
/// migration. These methods provide the required-default contract of 1.3.1.1
/// and 1.4.1.1, with invocation hooks and immutable hints in options.
extension RequiredDefaultEvaluation on FeatureClient {
  /// Evaluates a boolean flag with an explicit application fallback.
  Future<bool> getBooleanValue(
    String flagKey, {
    required bool defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async => (await getBooleanEvaluationDetails(
    flagKey,
    defaultValue: defaultValue,
    context: context,
    options: options,
  )).value;

  /// Detailed boolean evaluation with an explicit application fallback.
  Future<FlagEvaluationDetails<bool>> getBooleanEvaluationDetails(
    String flagKey, {
    required bool defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) => _withApplicationDefault(
    flagKey,
    defaultValue,
    () => getBooleanDetails(
      flagKey,
      defaultValue: defaultValue,
      context: context,
      options: options,
    ),
  );

  /// Evaluates a string flag with an explicit application fallback.
  Future<String> getStringValue(
    String flagKey, {
    required String defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async => (await getStringEvaluationDetails(
    flagKey,
    defaultValue: defaultValue,
    context: context,
    options: options,
  )).value;

  /// Detailed string evaluation with an explicit application fallback.
  Future<FlagEvaluationDetails<String>> getStringEvaluationDetails(
    String flagKey, {
    required String defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) => _withApplicationDefault(
    flagKey,
    defaultValue,
    () => getStringDetails(
      flagKey,
      defaultValue: defaultValue,
      context: context,
      options: options,
    ),
  );

  /// Evaluates a integer flag with an explicit application fallback.
  Future<int> getIntegerValue(
    String flagKey, {
    required int defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async => (await getIntegerEvaluationDetails(
    flagKey,
    defaultValue: defaultValue,
    context: context,
    options: options,
  )).value;

  /// Detailed integer evaluation with an explicit application fallback.
  Future<FlagEvaluationDetails<int>> getIntegerEvaluationDetails(
    String flagKey, {
    required int defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) => _withApplicationDefault(
    flagKey,
    defaultValue,
    () => getIntegerDetails(
      flagKey,
      defaultValue: defaultValue,
      context: context,
      options: options,
    ),
  );

  /// Evaluates a double flag with an explicit application fallback.
  Future<double> getDoubleValue(
    String flagKey, {
    required double defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async => (await getDoubleEvaluationDetails(
    flagKey,
    defaultValue: defaultValue,
    context: context,
    options: options,
  )).value;

  /// Detailed double evaluation with an explicit application fallback.
  Future<FlagEvaluationDetails<double>> getDoubleEvaluationDetails(
    String flagKey, {
    required double defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) => _withApplicationDefault(
    flagKey,
    defaultValue,
    () => getDoubleDetails(
      flagKey,
      defaultValue: defaultValue,
      context: context,
      options: options,
    ),
  );

  /// Evaluates a object flag with an explicit application fallback.
  Future<Map<String, dynamic>> getObjectValue(
    String flagKey, {
    required Map<String, dynamic> defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) async => (await getObjectEvaluationDetails(
    flagKey,
    defaultValue: defaultValue,
    context: context,
    options: options,
  )).value;

  /// Detailed object evaluation with an explicit application fallback.
  Future<FlagEvaluationDetails<Map<String, dynamic>>>
  getObjectEvaluationDetails(
    String flagKey, {
    required Map<String, dynamic> defaultValue,
    EvaluationContext? context,
    EvaluationOptions? options,
  }) => _withApplicationDefault(
    flagKey,
    defaultValue,
    () => getObjectDetails(
      flagKey,
      defaultValue: defaultValue,
      context: context,
      options: options,
    ),
  );
}

Future<FlagEvaluationDetails<T>> _withApplicationDefault<T>(
  String flagKey,
  T defaultValue,
  Future<FlagEvaluationDetails<T>> Function() evaluate,
) async {
  // Include provider resolution and all hook stages in the failure boundary.
  try {
    return await evaluate();
  } catch (error) {
    return FlagEvaluationDetails<T>(
      flagKey: flagKey,
      value: defaultValue,
      reason: 'ERROR',
      errorCode: error is ProviderException ? error.code : ErrorCode.GENERAL,
      errorMessage: _safeErrorMessage(error),
    );
  }
}

/// Legacy detailed evaluation methods; prefer get*EvaluationDetails for
/// compile-time enforcement of application-selected defaults.
///
/// Retained without analyzer deprecations until the documented migration stage.
/// Extension to add evaluation details methods
extension ClientEvaluationDetails on FeatureClient {
  /// Get boolean flag with full evaluation details
  Future<FlagEvaluationDetails<bool>> getBooleanDetails(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    bool defaultValue = false,
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) => evaluationProvider.getBooleanFlag(
        flagKey,
        defaultValue,
        context: ctx,
      ),
      context: context,
      options: options,
    );

    return FlagEvaluationDetails.fromResult(result);
  }

  /// Get string flag with full evaluation details
  Future<FlagEvaluationDetails<String>> getStringDetails(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    String defaultValue = '',
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getStringFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );

    return FlagEvaluationDetails.fromResult(result);
  }

  /// Get integer flag with full evaluation details
  Future<FlagEvaluationDetails<int>> getIntegerDetails(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    int defaultValue = 0,
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) => evaluationProvider.getIntegerFlag(
        flagKey,
        defaultValue,
        context: ctx,
      ),
      context: context,
      options: options,
    );

    return FlagEvaluationDetails.fromResult(result);
  }

  /// Get double flag with full evaluation details
  Future<FlagEvaluationDetails<double>> getDoubleDetails(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    double defaultValue = 0.0,
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getDoubleFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );

    return FlagEvaluationDetails.fromResult(result);
  }

  /// Get object flag with full evaluation details
  Future<FlagEvaluationDetails<Map<String, dynamic>>> getObjectDetails(
    String flagKey, {
    EvaluationContext? context,
    EvaluationOptions? options,
    Map<String, dynamic> defaultValue = const {},
  }) async {
    final result = await _evaluateFlagResult(
      flagKey,
      defaultValue,
      (evaluationProvider, ctx) =>
          evaluationProvider.getObjectFlag(flagKey, defaultValue, context: ctx),
      context: context,
      options: options,
    );

    return FlagEvaluationDetails.fromResult(result);
  }
}

String _safeErrorMessage(Object error) {
  try {
    return error.toString();
  } catch (_) {
    return 'Evaluation failed with an error that could not be formatted.';
  }
}
