import 'dart:async';
import 'dart:collection';

/// Provider states for lifecycle management
enum ProviderState {
  READY,
  ERROR,
  NOT_READY,
  STALE,
  SHUTDOWN,
  FATAL,
  CONNECTING,
  SYNCHRONIZING,
  DEGRADED,
  RECONNECTING,
  PLUGIN_ERROR,
  MAINTENANCE,
}

/// OpenFeature error codes
enum ErrorCode {
  FLAG_NOT_FOUND,
  TYPE_MISMATCH,
  GENERAL,
  PARSE_ERROR,
  TARGETING_KEY_MISSING,
  INVALID_CONTEXT,
  PROVIDER_NOT_READY,
  PROVIDER_FATAL,
}

/// Provider metadata
class ProviderMetadata {
  final String name;
  final String version;
  final Map<String, String> attributes;

  const ProviderMetadata({
    required this.name,
    this.version = '1.0.0',
    this.attributes = const {},
  });
}

/// Provider configuration
class ProviderConfig {
  final Duration connectionTimeout;
  final Duration operationTimeout;
  final int maxRetries;
  final Duration retryDelay;
  final bool enableCache;
  final Duration cacheTTL;
  final int maxCacheSize;
  final Map<String, dynamic> customConfig;

  const ProviderConfig({
    this.connectionTimeout = const Duration(seconds: 30),
    this.operationTimeout = const Duration(seconds: 5),
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.enableCache = true,
    this.cacheTTL = const Duration(minutes: 5),
    this.maxCacheSize = 1000,
    this.customConfig = const {},
  });
}

/// Cache entry for provider-level caching
class _ProviderCacheEntry<T> {
  final T value;
  final DateTime expiresAt;
  final String contextHash;

  _ProviderCacheEntry({
    required this.value,
    required Duration ttl,
    required this.contextHash,
  }) : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Result of feature flag evaluation
class FlagEvaluationResult<T> {
  final String flagKey;
  final T value;
  final String reason;
  final String? variant;
  final ErrorCode? errorCode;
  final String? errorMessage;
  final Map<String, dynamic> flagMetadata;
  final Map<String, dynamic>? details;
  final DateTime evaluatedAt;
  final String evaluatorId;

  const FlagEvaluationResult({
    required this.flagKey,
    required this.value,
    this.reason = 'DEFAULT',
    this.variant,
    this.errorCode,
    this.errorMessage,
    this.flagMetadata = const {},
    this.details,
    required this.evaluatedAt,
    this.evaluatorId = '',
  });

  /// Create an error result
  static FlagEvaluationResult<T> error<T>(
    String flagKey,
    T defaultValue,
    ErrorCode errorCode,
    String message, {
    String evaluatorId = '',
  }) {
    return FlagEvaluationResult<T>(
      flagKey: flagKey,
      value: defaultValue,
      reason: 'ERROR',
      errorCode: errorCode,
      errorMessage: message,
      evaluatedAt: DateTime.now(),
      evaluatorId: evaluatorId,
    );
  }
}

/// Evaluation details containing full context about flag evaluation
class FlagEvaluationDetails<T> {
  final String flagKey;
  final T value;
  final ErrorCode? errorCode;
  final String? errorMessage;
  final String? reason;
  final String? variant;
  final Map<String, dynamic> flagMetadata;
  final DateTime timestamp;

  FlagEvaluationDetails({
    required this.flagKey,
    required this.value,
    this.errorCode,
    this.errorMessage,
    this.reason,
    this.variant,
    Map<String, dynamic> flagMetadata = const {},
    DateTime? timestamp,
  }) : flagMetadata = Map.unmodifiable(flagMetadata),
       timestamp = timestamp ?? DateTime.now();

  factory FlagEvaluationDetails.fromResult(FlagEvaluationResult<T> result) {
    return FlagEvaluationDetails(
      flagKey: result.flagKey,
      value: result.value,
      errorCode: result.errorCode,
      errorMessage: result.errorMessage,
      reason: result.reason,
      variant: result.variant,
      flagMetadata: result.flagMetadata,
      timestamp: result.evaluatedAt,
    );
  }
}

/// Provider exception
class ProviderException implements Exception {
  final String message;
  final ErrorCode code;
  final Map<String, dynamic>? details;

  const ProviderException(
    this.message, {
    this.code = ErrorCode.GENERAL,
    this.details,
  });

  @override
  String toString() => 'ProviderException: $message (code: ${code.name})';
}

/// Tracking event details for the Tracking API (spec Section 6)
class TrackingEventDetails {
  final double? value;
  final Map<String, dynamic> attributes;

  const TrackingEventDetails({this.value, this.attributes = const {}});
}

/// Minimal provider contract: metadata and five typed resolvers (2.1-2.2).
/// Initialization, shutdown, hooks and tracking are optional capabilities
/// declared in provider_capabilities.dart.
abstract interface class Provider {
  ProviderMetadata get metadata;

  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  });
}

/// Source-compatible provider interface for existing implementations.
/// New implementations can implement [Provider] and optional capabilities.
abstract class FeatureProvider implements Provider {
  String get name;
  ProviderState get state;
  ProviderConfig get config;
  ProviderMetadata get metadata;

  Future<void> initialize([Map<String, dynamic>? config]);
  Future<void> connect();
  Future<void> shutdown();

  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  });

  /// Tracking API (spec Section 6) - record a tracking event
  /// Providers that do not support tracking should silently no-op.
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  });
}

/// Base provider with caching capabilities
abstract class CachedFeatureProvider implements FeatureProvider {
  final ProviderConfig _config;
  final ProviderMetadata _metadata;
  ProviderState _state = ProviderState.NOT_READY;

  // Provider-level cache
  final LinkedHashMap<String, _ProviderCacheEntry<dynamic>> _cache =
      LinkedHashMap<String, _ProviderCacheEntry<dynamic>>();

  CachedFeatureProvider({
    required ProviderMetadata metadata,
    ProviderConfig? config,
  }) : _metadata = metadata,
       _config = config ?? const ProviderConfig();

  @override
  ProviderState get state => _state;

  @override
  ProviderConfig get config => _config;

  @override
  ProviderMetadata get metadata => _metadata;

  @override
  String get name => _metadata.name;

  /// Set provider state
  void setState(ProviderState newState) {
    _state = newState;
  }

  /// Generate cache key
  String _generateCacheKey(String flagKey, Map<String, dynamic>? context) {
    final buffer = StringBuffer(flagKey);
    if (context != null) {
      final sortedKeys = context.keys.toList()..sort();
      for (final key in sortedKeys) {
        buffer.write('$key:${context[key]}');
      }
    }
    return buffer.toString();
  }

  /// Add to cache
  void _addToCache<T>(String key, T value) {
    if (!_config.enableCache) return;

    // Remove oldest entries if cache is full
    while (_cache.length >= _config.maxCacheSize) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = _ProviderCacheEntry<T>(
      value: value,
      ttl: _config.cacheTTL,
      contextHash: key,
    );
  }

  /// Get cache entry with reason
  _ProviderCacheEntry<T>? _getCacheEntry<T>(String key) {
    if (!_config.enableCache) return null;

    final entry = _cache[key];
    if (entry == null || entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry as _ProviderCacheEntry<T>?;
  }

  /// Clear cache
  void clearCache() {
    _cache.clear();
  }

  /// Abstract methods for actual flag resolution
  Future<FlagEvaluationResult<bool>> resolveBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<String>> resolveStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<int>> resolveIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<double>> resolveDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  });

  Future<FlagEvaluationResult<Map<String, dynamic>>> resolveObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  });

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final cacheKey = _generateCacheKey(flagKey, context);
    final cachedEntry = _getCacheEntry<bool>(cacheKey);

    if (cachedEntry != null) {
      return FlagEvaluationResult(
        flagKey: flagKey,
        value: cachedEntry.value,
        reason: 'CACHED',
        evaluatedAt: DateTime.now(),
        evaluatorId: name,
      );
    }

    final result = await resolveBooleanFlag(
      flagKey,
      defaultValue,
      context: context,
    );

    if (result.errorCode == null) {
      _addToCache(cacheKey, result.value);
    }

    return result;
  }

  @override
  Future<FlagEvaluationResult<String>> getStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final cacheKey = _generateCacheKey(flagKey, context);
    final cachedEntry = _getCacheEntry<String>(cacheKey);

    if (cachedEntry != null) {
      return FlagEvaluationResult(
        flagKey: flagKey,
        value: cachedEntry.value,
        reason: 'CACHED',
        evaluatedAt: DateTime.now(),
        evaluatorId: name,
      );
    }

    final result = await resolveStringFlag(
      flagKey,
      defaultValue,
      context: context,
    );

    if (result.errorCode == null) {
      _addToCache(cacheKey, result.value);
    }

    return result;
  }

  @override
  Future<FlagEvaluationResult<int>> getIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final cacheKey = _generateCacheKey(flagKey, context);
    final cachedEntry = _getCacheEntry<int>(cacheKey);

    if (cachedEntry != null) {
      return FlagEvaluationResult(
        flagKey: flagKey,
        value: cachedEntry.value,
        reason: 'CACHED',
        evaluatedAt: DateTime.now(),
        evaluatorId: name,
      );
    }

    final result = await resolveIntegerFlag(
      flagKey,
      defaultValue,
      context: context,
    );

    if (result.errorCode == null) {
      _addToCache(cacheKey, result.value);
    }

    return result;
  }

  @override
  Future<FlagEvaluationResult<double>> getDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final cacheKey = _generateCacheKey(flagKey, context);
    final cachedEntry = _getCacheEntry<double>(cacheKey);

    if (cachedEntry != null) {
      return FlagEvaluationResult(
        flagKey: flagKey,
        value: cachedEntry.value,
        reason: 'CACHED',
        evaluatedAt: DateTime.now(),
        evaluatorId: name,
      );
    }

    final result = await resolveDoubleFlag(
      flagKey,
      defaultValue,
      context: context,
    );

    if (result.errorCode == null) {
      _addToCache(cacheKey, result.value);
    }

    return result;
  }

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> getObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    final cacheKey = _generateCacheKey(flagKey, context);
    final cachedEntry = _getCacheEntry<Map<String, dynamic>>(cacheKey);

    if (cachedEntry != null) {
      return FlagEvaluationResult(
        flagKey: flagKey,
        value: cachedEntry.value,
        reason: 'CACHED',
        evaluatedAt: DateTime.now(),
        evaluatorId: name,
      );
    }

    final result = await resolveObjectFlag(
      flagKey,
      defaultValue,
      context: context,
    );

    if (result.errorCode == null) {
      _addToCache(cacheKey, result.value);
    }

    return result;
  }

  /// Default track implementation - silently no-ops per spec
  @override
  Future<void> track(
    String trackingEventName, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async {
    // Default: no-op. Subclasses that support tracking should override.
  }
}

/// In-memory provider implementation with caching - FIXED for synchronous default provider
class InMemoryProvider extends CachedFeatureProvider {
  final Map<String, dynamic> _flags;

  InMemoryProvider(this._flags, [ProviderConfig? config])
    : super(
        metadata: const ProviderMetadata(name: 'InMemoryProvider'),
        config: config,
      );

  @override
  Future<void> initialize([Map<String, dynamic>? config]) async {
    if (state == ProviderState.SHUTDOWN) {
      throw ProviderException(
        'Cannot initialize a shutdown provider',
        code: ErrorCode.PROVIDER_NOT_READY,
      );
    }

    setState(ProviderState.CONNECTING);

    try {
      // Simulate initialization work
      await Future.delayed(Duration(milliseconds: 10));
      setState(ProviderState.READY);
    } catch (e) {
      setState(ProviderState.ERROR);
      rethrow;
    }
  }

  @override
  Future<void> connect() async {
    if (state == ProviderState.SHUTDOWN) {
      throw ProviderException(
        'Cannot connect a shutdown provider',
        code: ErrorCode.PROVIDER_NOT_READY,
      );
    }

    setState(ProviderState.CONNECTING);

    try {
      await Future.delayed(Duration(milliseconds: 10));
      setState(ProviderState.READY);
    } catch (e) {
      setState(ProviderState.ERROR);
      rethrow;
    }
  }

  @override
  Future<void> shutdown() async {
    clearCache();
    setState(ProviderState.SHUTDOWN);
  }

  void _checkState() {
    if (state != ProviderState.READY) {
      throw ProviderException(
        'Provider not in READY state: ${state.name}',
        code: ErrorCode.PROVIDER_NOT_READY,
        details: {'currentState': state.name},
      );
    }
  }

  @override
  Future<FlagEvaluationResult<bool>> resolveBooleanFlag(
    String flagKey,
    bool defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    _checkState();

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! bool) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Flag "$flagKey" is not a boolean, got ${value.runtimeType}',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<String>> resolveStringFlag(
    String flagKey,
    String defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    _checkState();

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! String) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Flag "$flagKey" is not a string, got ${value.runtimeType}',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<int>> resolveIntegerFlag(
    String flagKey,
    int defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    _checkState();

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! int) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Flag "$flagKey" is not an integer, got ${value.runtimeType}',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<double>> resolveDoubleFlag(
    String flagKey,
    double defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    _checkState();

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! double) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Flag "$flagKey" is not a double, got ${value.runtimeType}',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }

  @override
  Future<FlagEvaluationResult<Map<String, dynamic>>> resolveObjectFlag(
    String flagKey,
    Map<String, dynamic> defaultValue, {
    Map<String, dynamic>? context,
  }) async {
    _checkState();

    if (!_flags.containsKey(flagKey)) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.FLAG_NOT_FOUND,
        'Flag "$flagKey" not found',
        evaluatorId: name,
      );
    }

    final value = _flags[flagKey];
    if (value is! Map<String, dynamic>) {
      return FlagEvaluationResult.error(
        flagKey,
        defaultValue,
        ErrorCode.TYPE_MISMATCH,
        'Flag "$flagKey" is not an object, got ${value.runtimeType}',
        evaluatorId: name,
      );
    }

    return FlagEvaluationResult(
      flagKey: flagKey,
      value: value,
      reason: 'STATIC',
      evaluatedAt: DateTime.now(),
      evaluatorId: name,
    );
  }
}
