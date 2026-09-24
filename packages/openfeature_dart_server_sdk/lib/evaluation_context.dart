// Evaluation context definition and merging logic.
// Implementation of the evaluation context for feature flag decisions
// Extends the existing basic context to support hierarchical contexts and targeting rules

import 'dart:collection';
import 'src/context_snapshot.dart';

/// Represents a targeting rule operator
enum TargetingOperator {
  EQUALS,
  NOT_EQUALS,
  CONTAINS,
  NOT_CONTAINS,
  STARTS_WITH,
  ENDS_WITH,
  GREATER_THAN,
  LESS_THAN,
  IN_LIST,
  NOT_IN_LIST,
  MATCHES_REGEX,
  VERSION_GREATER_THAN,
  VERSION_LESS_THAN,
  SEMANTIC_VERSION_MATCH,
}

/// Cache entry for evaluation results
class EvaluationCacheEntry {
  final dynamic result;
  final DateTime expiresAt;
  final String contextHash;

  EvaluationCacheEntry({
    required this.result,
    required this.expiresAt,
    required this.contextHash,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Represents a targeting rule for feature flag evaluation
class TargetingRule {
  final String attribute;
  final TargetingOperator operator;
  final dynamic value;
  final Map<String, dynamic>? metadata;
  final List<TargetingRule> subRules;

  const TargetingRule(
    this.attribute,
    this.operator,
    this.value, {
    this.metadata,
    this.subRules = const [],
  });

  /// Evaluate the rule against a context
  bool evaluate(Map<String, dynamic> context) {
    final attributeValue = context[attribute];
    if (attributeValue == null) return false;

    bool result = _evaluateCore(attributeValue);

    // Evaluate sub-rules if they exist
    if (result && subRules.isNotEmpty) {
      return subRules.every((rule) => rule.evaluate(context));
    }

    return result;
  }

  bool _evaluateCore(dynamic attributeValue) {
    switch (operator) {
      case TargetingOperator.EQUALS:
        return attributeValue == value;
      case TargetingOperator.NOT_EQUALS:
        return attributeValue != value;
      case TargetingOperator.CONTAINS:
        return attributeValue.toString().contains(value.toString());
      case TargetingOperator.NOT_CONTAINS:
        return !attributeValue.toString().contains(value.toString());
      case TargetingOperator.STARTS_WITH:
        return attributeValue.toString().startsWith(value.toString());
      case TargetingOperator.ENDS_WITH:
        return attributeValue.toString().endsWith(value.toString());
      case TargetingOperator.GREATER_THAN:
        return (attributeValue as num) > (value as num);
      case TargetingOperator.LESS_THAN:
        return (attributeValue as num) < (value as num);
      case TargetingOperator.IN_LIST:
        return (value as List).contains(attributeValue);
      case TargetingOperator.NOT_IN_LIST:
        return !(value as List).contains(attributeValue);
      case TargetingOperator.MATCHES_REGEX:
        return RegExp(value.toString()).hasMatch(attributeValue.toString());
      case TargetingOperator.VERSION_GREATER_THAN:
        return _compareVersions(attributeValue.toString(), value.toString()) >
            0;
      case TargetingOperator.VERSION_LESS_THAN:
        return _compareVersions(attributeValue.toString(), value.toString()) <
            0;
      case TargetingOperator.SEMANTIC_VERSION_MATCH:
        return _matchSemanticVersion(
          attributeValue.toString(),
          value.toString(),
        );
    }
  }

  int _compareVersions(String v1, String v2) {
    var v1Parts = v1.split('.');
    var v2Parts = v2.split('.');

    for (var i = 0; i < v1Parts.length && i < v2Parts.length; i++) {
      var v1Part = int.parse(v1Parts[i]);
      var v2Part = int.parse(v2Parts[i]);
      if (v1Part != v2Part) return v1Part.compareTo(v2Part);
    }
    return v1Parts.length.compareTo(v2Parts.length);
  }

  bool _matchSemanticVersion(String version, String pattern) {
    return RegExp(pattern).hasMatch(version);
  }
}

/// Cache manager for evaluation results
class _EvaluationCache {
  static const maxSize = 1000;
  final _cache = LinkedHashMap<String, EvaluationCacheEntry>();

  dynamic get(String key) {
    final entry = _cache[key];
    if (entry == null || entry.isExpired) {
      _cache.remove(key);
      return null;
    }
    return entry.result;
  }

  void set(String key, dynamic value, Duration ttl) {
    if (_cache.length >= maxSize) {
      _cache.remove(_cache.keys.first);
    }

    _cache[key] = EvaluationCacheEntry(
      result: value,
      expiresAt: DateTime.now().add(ttl),
      contextHash: key,
    );
  }

  void clear() => _cache.clear();
}

/// Canonical evaluation context with optional legacy targeting helpers.
/// Use [EvaluationContext.immutable] to snapshot caller-owned data immediately.
class EvaluationContext {
  final String? targetingKey;
  final Map<String, dynamic> attributes;
  final EvaluationContext? parent;
  final List<TargetingRule> rules;
  final Duration cacheDuration;
  final Map<String, dynamic>? _providerSnapshot;
  static final _cache = _EvaluationCache();

  /// Legacy const-compatible construction, retaining caller-owned values.
  /// Use [EvaluationContext.immutable] to opt into deep snapshot semantics.
  const EvaluationContext({
    this.targetingKey,
    required this.attributes,
    this.parent,
    this.rules = const [],
    this.cacheDuration = const Duration(minutes: 5),
  }) : _providerSnapshot = null;

  EvaluationContext._snapshot({
    required this.targetingKey,
    required this.attributes,
    required this.parent,
    required this.rules,
    required this.cacheDuration,
  }) : _providerSnapshot = Map<String, dynamic>.unmodifiable({
         ...?parent?.toProviderContext(),
         ...attributes,
       });

  /// Copies and freezes evaluation fields, including nested maps/lists.
  /// Rule operands outside maps/lists are retained by reference; callers must
  /// keep custom mutable operands stable for the lifetime of the snapshot.
  /// The map-form `targetingKey` is a compatibility alias for [targetingKey];
  /// an explicit argument takes precedence at the same context level.
  factory EvaluationContext.immutable({
    String? targetingKey,
    Map<String, dynamic> attributes = const {},
    EvaluationContext? parent,
    List<TargetingRule> rules = const [],
    Duration cacheDuration = const Duration(minutes: 5),
  }) {
    final mapKey = attributes['targetingKey'];
    if (attributes.containsKey('targetingKey') && mapKey is! String) {
      throw InvalidContextException('attributes.targetingKey must be a string');
    }
    final localKey = targetingKey ?? mapKey as String?;
    final copied = snapshotContextMap({
      ...attributes,
      if (localKey != null) 'targetingKey': localKey,
    });
    return EvaluationContext._snapshot(
      targetingKey: localKey,
      attributes: copied,
      parent: parent?.snapshot(),
      rules: _snapshotRules(rules, HashSet<TargetingRule>.identity(), 'rules'),
      cacheDuration: cacheDuration,
    );
  }

  /// Captures a legacy context and its complete parent chain for SDK use.
  EvaluationContext snapshot() => _providerSnapshot != null
      ? this
      : EvaluationContext.immutable(
          targetingKey: targetingKey,
          attributes: attributes,
          parent: parent,
          rules: rules,
          cacheDuration: cacheDuration,
        );

  /// Return the complete context in the legacy provider-map representation.
  ///
  /// Parent fields have the lowest precedence. The targeting key is emitted as
  /// `targetingKey` so providers using the map-based compatibility interface do
  /// not lose the subject of the evaluation.
  Map<String, dynamic> toProviderContext() {
    if (_providerSnapshot != null) return _providerSnapshot;
    final result = <String, dynamic>{
      ...parent?.toProviderContext() ?? const <String, dynamic>{},
      ...attributes,
    };
    if (targetingKey != null) {
      result['targetingKey'] = targetingKey;
    }
    return result;
  }

  /// Get an attribute value, checking parent context if not found
  dynamic getAttribute(String key) {
    if (key == 'targetingKey' && targetingKey != null) return targetingKey;
    if (_providerSnapshot != null && attributes.containsKey(key)) {
      return attributes[key];
    }
    return attributes[key] ?? parent?.getAttribute(key);
  }

  /// Create a new context by merging with another
  /// Explicit keys precede map aliases and inherited keys; the right explicit
  /// key wins over the left explicit key.
  /// SDK context levels are merged separately in API -> transaction -> client
  /// -> invocation order. Mixing in a legacy context retains legacy semantics.
  EvaluationContext merge(EvaluationContext other) {
    final merged = {...toProviderContext(), ...other.toProviderContext()};
    String? localKey(EvaluationContext context) =>
        context.targetingKey ??
        (context.attributes['targetingKey'] is String
            ? context.attributes['targetingKey'] as String
            : null);
    final key =
        other.targetingKey ?? targetingKey ?? localKey(other) ?? localKey(this);
    if (key != null) merged['targetingKey'] = key;
    final mergedRules = [...rules, ...other.rules];
    if (_providerSnapshot != null && other._providerSnapshot != null) {
      return EvaluationContext.immutable(
        targetingKey: key,
        attributes: merged,
        rules: mergedRules,
        cacheDuration: cacheDuration,
      );
    }
    return EvaluationContext(
      targetingKey: key,
      attributes: merged,
      rules: mergedRules,
      cacheDuration: cacheDuration,
    );
  }

  /// Generate cache key for current context
  String _generateCacheKey() {
    final buffer = StringBuffer();
    void addToKey(EvaluationContext? context) {
      if (context == null) return;
      addToKey(context.parent);
      if (context.targetingKey != null) {
        buffer.write('tk:${context.targetingKey}|');
      }
      buffer.write(context.attributes.toString());
      buffer.write(context.rules.toString());
    }

    addToKey(this);
    return buffer.toString();
  }

  /// Evaluate all targeting rules with caching
  Future<bool> evaluateRules() async {
    final cacheKey = _generateCacheKey();

    // Check cache
    final cachedResult = _cache.get(cacheKey);
    if (cachedResult != null) return cachedResult as bool;

    // Evaluate parent rules
    if (parent != null && !await parent!.evaluateRules()) {
      _cache.set(cacheKey, false, cacheDuration);
      return false;
    }

    // Evaluate current rules
    bool result = rules.every((rule) => rule.evaluate(attributes));
    _cache.set(cacheKey, result, cacheDuration);
    return result;
  }

  /// Create a child context
  EvaluationContext createChild(
    Map<String, dynamic> childAttributes, {
    String? childTargetingKey,
    List<TargetingRule>? childRules,
    Duration? childCacheDuration,
  }) {
    if (_providerSnapshot != null) {
      return EvaluationContext.immutable(
        targetingKey: childTargetingKey ?? targetingKey,
        attributes: childAttributes,
        parent: this,
        rules: childRules ?? [],
        cacheDuration: childCacheDuration ?? cacheDuration,
      );
    }
    return EvaluationContext(
      targetingKey: childTargetingKey ?? targetingKey,
      attributes: childAttributes,
      parent: this,
      rules: childRules ?? [],
      cacheDuration: childCacheDuration ?? cacheDuration,
    );
  }
}

List<TargetingRule> _snapshotRules(
  List<TargetingRule> rules,
  Set<TargetingRule> ancestors,
  String path,
) => List<TargetingRule>.unmodifiable([
  for (var i = 0; i < rules.length; i++)
    _snapshotRule(rules[i], ancestors, '$path[$i]'),
]);

TargetingRule _snapshotRule(
  TargetingRule rule,
  Set<TargetingRule> ancestors,
  String path,
) {
  if (!ancestors.add(rule)) {
    throw InvalidContextException('$path must be acyclic');
  }
  try {
    return TargetingRule(
      rule.attribute,
      rule.operator,
      _snapshotRuleValue(rule.value, '$path.value', HashSet<Object>.identity()),
      metadata: rule.metadata == null
          ? null
          : snapshotContextMap(rule.metadata!, path: '$path.metadata'),
      subRules: _snapshotRules(rule.subRules, ancestors, '$path.subRules'),
    );
  } finally {
    ancestors.remove(rule);
  }
}

// Rule operands have a wider value model than context attributes. Freeze their
// maps/lists without imposing the attribute scalar or string-key restrictions.
dynamic _snapshotRuleValue(dynamic value, String path, Set<Object> ancestors) {
  if (value is! List && value is! Map) return value;
  if (!ancestors.add(value)) {
    throw InvalidContextException('$path: structures must be acyclic');
  }
  try {
    if (value is List) {
      return List<dynamic>.unmodifiable([
        for (var i = 0; i < value.length; i++)
          _snapshotRuleValue(value[i], '$path[$i]', ancestors),
      ]);
    }
    final result = <dynamic, dynamic>{};
    var index = 0;
    for (final entry in (value as Map).entries) {
      final key = _snapshotRuleValue(
        entry.key,
        '$path.keys[$index]',
        ancestors,
      );
      result[key] = _snapshotRuleValue(
        entry.value,
        '$path.values[$index]',
        ancestors,
      );
      index++;
    }
    return Map<dynamic, dynamic>.unmodifiable(result);
  } finally {
    ancestors.remove(value);
  }
}
