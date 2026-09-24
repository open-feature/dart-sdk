import 'immutable.dart';

/// Distinguishes explicit context validation from unrelated provider failures.
class InvalidContextException extends ArgumentError implements Exception {
  InvalidContextException(String message) : super(message);
}

/// Validates and snapshots the opt-in context value model.
dynamic snapshotContextValue(dynamic value, {String path = 'attributes'}) {
  try {
    return immutableValue(value, path: path);
  } on ArgumentError catch (error) {
    throw InvalidContextException(error.message.toString());
  }
}

/// Copies string-keyed structures, accepting null at every depth.
Map<String, dynamic> snapshotContextMap(
  Map<String, dynamic> attributes, {
  String path = 'attributes',
}) => snapshotContextValue(attributes, path: path) as Map<String, dynamic>;
