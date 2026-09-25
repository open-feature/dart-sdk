import 'dart:async';

import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:test/test.dart';

bool isTerminalProviderEvent(ProviderEvent event) => const {
  ProviderEventType.ready,
  ProviderEventType.error,
  ProviderEventType.contextChanged,
}.contains(event.type);

/// Observe before invoking [action], then wait for a quiet interval after both
/// the action and (when requested) a terminal event. Every event resets that
/// interval. The deadline bounds the entire operation, including noisy streams.
/// This is bounded evidence; it cannot exclude events after the quiet interval.
Future<List<ProviderEvent>> observeProviderEvents(
  Stream<ProviderEvent> stream,
  Future<void> Function() action, {
  bool requireTerminal = false,
  Duration quietPeriod = const Duration(milliseconds: 100),
  Duration timeout = const Duration(seconds: 3),
}) async {
  final result = Completer<List<ProviderEvent>>();
  final events = <ProviderEvent>[];
  var actionDone = false;
  var terminalSeen = false;
  Timer? quiet;
  final deadline = Timer(timeout, () {
    if (!result.isCompleted) {
      result.completeError(
        TimeoutException('Provider action/events did not settle', timeout),
      );
    }
  });

  void settle() {
    quiet?.cancel();
    if (!result.isCompleted &&
        actionDone &&
        (!requireTerminal || terminalSeen)) {
      quiet = Timer(quietPeriod, () {
        if (!result.isCompleted) result.complete(List.of(events));
      });
    }
  }

  void fail(Object error, StackTrace stack) {
    if (!result.isCompleted) result.completeError(error, stack);
  }

  final subscription = stream.listen((event) {
    if (result.isCompleted) return;
    events.add(event);
    terminalSeen |= isTerminalProviderEvent(event);
    settle();
  }, onError: fail);
  try {
    // Future.sync also captures a synchronous throw. Retain an error handler
    // if an action completes after the observation deadline.
    unawaited(
      Future<void>.sync(action).then((_) {
        actionDone = true;
        settle();
      }, onError: fail),
    );
    return await result.future;
  } finally {
    quiet?.cancel();
    deadline.cancel();
    await subscription.cancel();
  }
}

Future<void> expectProviderTransition(
  Stream<ProviderEvent> stream,
  Future<void> Function() action,
  ProviderEventType expected,
) async {
  final events = await observeProviderEvents(
    stream,
    action,
    requireTerminal: true,
  );
  expect(
    events.where(isTerminalProviderEvent).map((event) => event.type),
    [expected],
    reason:
        'The provider itself must emit exactly one terminal event for this transition',
  );
}

Future<void> expectNoProviderEvents(
  Stream<ProviderEvent> stream,
  Future<void> Function() action,
) async {
  expect(
    await observeProviderEvents(stream, action),
    isEmpty,
    reason: 'Repeated shutdown must not emit a new transition',
  );
}
