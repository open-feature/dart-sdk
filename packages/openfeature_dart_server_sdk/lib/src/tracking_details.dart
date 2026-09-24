import 'dart:collection';

/// JSON-shaped tracking details. Null is supported within a structure, but a
/// top-level custom field must be a boolean, string, number, map or list.
Map<String, dynamic> snapshotTrackingDetails(Map<String, dynamic> fields) {
  final ancestors = HashSet<Object>.identity();
  Object? copy(Object? value, String path, {bool nested = false}) {
    if (value is bool || value is String || value is num) return value;
    if (nested && value == null) return null;
    if (value is Map || value is List) {
      if (!ancestors.add(value!)) {
        throw ArgumentError('$path: structures must be acyclic');
      }
      try {
        if (value is List) {
          return List<Object?>.unmodifiable([
            for (var i = 0; i < value.length; i++)
              copy(value[i], '$path[$i]', nested: true),
          ]);
        }
        final result = <String, Object?>{};
        for (final entry in (value as Map).entries) {
          if (entry.key is! String) {
            throw ArgumentError('$path: structure keys must be strings');
          }
          result[entry.key as String] = copy(
            entry.value,
            '$path.${entry.key}',
            nested: true,
          );
        }
        return Map<String, Object?>.unmodifiable(result);
      } finally {
        ancestors.remove(value);
      }
    }
    throw ArgumentError(
      '$path: unsupported tracking value type ${value.runtimeType}',
    );
  }

  return Map<String, dynamic>.unmodifiable({
    for (final entry in fields.entries)
      entry.key: copy(entry.value, 'attributes.${entry.key}'),
  });
}
