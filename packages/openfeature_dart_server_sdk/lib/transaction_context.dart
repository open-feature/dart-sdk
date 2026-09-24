import 'dart:async';
import 'package:meta/meta.dart';

/// Transaction context holder
class TransactionContext {
  final String transactionId;
  final Map<String, dynamic> attributes;
  final TransactionContext? parent;
  final DateTime createdAt;
  Timer? _cleanupTimer;

  TransactionContext({
    required this.transactionId,
    required this.attributes,
    this.parent,
  }) : createdAt = DateTime.now();

  Map<String, dynamic> get effectiveAttributes {
    final parentAttrs = parent?.effectiveAttributes ?? {};
    return {...parentAttrs, ...attributes};
  }

  void scheduleCleanup(Duration timeout) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer(timeout, cleanup);
  }

  @mustCallSuper
  void cleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }
}

/// Transaction context manager
class TransactionContextManager {
  static final TransactionContextManager _instance =
      TransactionContextManager._internal();
  static final Object _zoneContextsKey = Object();
  static final Object _zoneStackKey = Object();
  final _fallbackContexts = <String, TransactionContext>{};
  final _fallbackStack = <String>[];

  TransactionContextManager._internal();

  factory TransactionContextManager() => _instance;

  Map<String, TransactionContext> get _contexts =>
      Zone.current[_zoneContextsKey] as Map<String, TransactionContext>? ??
      _fallbackContexts;

  List<String> get _contextStack =>
      Zone.current[_zoneStackKey] as List<String>? ?? _fallbackStack;

  TransactionContext? get currentContext {
    if (_contextStack.isEmpty) return null;
    return _contexts[_contextStack.last];
  }

  void pushContext(TransactionContext context, {Duration? timeout}) {
    _contexts[context.transactionId] = context;
    _contextStack.add(context.transactionId);
    context.scheduleCleanup(timeout ?? const Duration(minutes: 5));
  }

  TransactionContext? popContext() {
    if (_contextStack.isEmpty) return null;
    final contextId = _contextStack.removeLast();
    final context = _contexts.remove(contextId);
    context?.cleanup();
    return context;
  }

  void clearContext(String transactionId) {
    final context = _contexts.remove(transactionId);
    if (context != null) {
      _contextStack.remove(transactionId);
      context.cleanup();
    }
  }

  TransactionContext createChildContext(
    String transactionId,
    Map<String, dynamic> attributes,
  ) {
    final parent = currentContext;
    return TransactionContext(
      transactionId: transactionId,
      attributes: attributes,
      parent: parent,
    );
  }

  /// Run code with a specific transaction context
  Future<T> withContext<T>(
    String transactionId,
    Map<String, dynamic> attributes,
    Future<T> Function() operation,
  ) async {
    final zoneContexts = Map<String, TransactionContext>.from(_contexts);
    final zoneStack = List<String>.from(_contextStack);

    return await runZoned(() async {
      final context = TransactionContext(
        transactionId: transactionId,
        attributes: attributes,
        parent: currentContext,
      );

      pushContext(context);
      try {
        return await operation();
      } finally {
        popContext();
      }
    }, zoneValues: {_zoneContextsKey: zoneContexts, _zoneStackKey: zoneStack});
  }

  void cleanup() {
    for (final context in _contexts.values) {
      context.cleanup();
    }
    _contexts.clear();
    _contextStack.clear();
  }
}
