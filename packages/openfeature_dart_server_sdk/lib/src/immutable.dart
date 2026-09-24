// Kept identical in both independently published SDKs by a repository test.
import 'dart:collection';

Object? immutableValue(Object? value, {String path = 'value'}) =>
    _immutableValue(value, path, HashSet<Object>.identity());

Object? _immutableValue(Object? value, String path, Set<Object> ancestors) {
  if (value == null ||
      value is bool ||
      value is String ||
      value is num ||
      value is DateTime) {
    return value;
  }
  if (value is List || value is Map) {
    if (!ancestors.add(value)) {
      throw ArgumentError('$path: structures must be acyclic');
    }
    try {
      if (value is List) {
        return List<Object?>.unmodifiable([
          for (var i = 0; i < value.length; i++)
            _immutableValue(value[i], '$path[$i]', ancestors),
        ]);
      }
      final result = <String, Object?>{};
      for (final entry in (value as Map).entries) {
        final key = entry.key;
        if (key is! String) {
          throw ArgumentError('$path: map keys must be strings');
        }
        result[key] = _immutableValue(entry.value, '$path.$key', ancestors);
      }
      return Map<String, Object?>.unmodifiable(result);
    } finally {
      ancestors.remove(value);
    }
  }
  // Include the location and type, not potentially sensitive context values.
  throw ArgumentError(
    '$path: unsupported context value type ${value.runtimeType}',
  );
}

Map<String, Object?> immutableStructure(
  Map<String, Object?> value, {
  String path = 'value',
}) => immutableValue(value, path: path)! as Map<String, Object?>;

Map<String, Object> immutableMetadata(
  Map<String, Object> value, {
  String path = 'metadata',
}) {
  final result = <String, Object>{};
  for (final entry in value.entries) {
    final metadataValue = entry.value;
    if (metadataValue is! bool &&
        metadataValue is! String &&
        metadataValue is! num) {
      throw ArgumentError(
        '$path.${entry.key}: metadata values must be bool, String, or num',
      );
    }
    result[entry.key] = metadataValue;
  }
  return Map<String, Object>.unmodifiable(result);
}
