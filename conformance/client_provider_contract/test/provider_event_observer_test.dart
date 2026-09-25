import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:openfeature_client_provider_contract/src/provider_event_observer.dart';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk.dart';
import 'package:test/test.dart';

class Outcome {
  bool done = false;
  Object? error;

  Outcome(Future<void> operation) {
    unawaited(
      operation.then(
        (_) => done = true,
        onError: (Object failure, StackTrace _) {
          error = failure;
          done = true;
        },
      ),
    );
  }
}

void main() {
  for (final delay in [Duration.zero, const Duration(milliseconds: 30)]) {
    test('C13 accepts exactly one error after $delay', () {
      fakeAsync((clock) {
        final events = StreamController<ProviderEvent>(
          sync: true,
          onCancel: () async {},
        );
        final result = Outcome(
          expectProviderTransition(events.stream, () async {
            void emit() =>
                events.add(ProviderEvent(type: ProviderEventType.error));
            if (delay == Duration.zero) {
              emit();
            } else {
              Timer(delay, emit);
            }
          }, ProviderEventType.error),
        );
        clock.flushMicrotasks();
        expect(result.done, isFalse);
        clock.elapse(const Duration(milliseconds: 200));
        expect(result.done, isTrue);
        expect(result.error, isNull);
        expect(events.hasListener, isFalse);
        expect(clock.pendingTimers, isEmpty);
        unawaited(events.close());
      });
    });
  }

  test('C13 rejects a delayed duplicate terminal event', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final result = Outcome(
        expectProviderTransition(events.stream, () async {
          events.add(ProviderEvent(type: ProviderEventType.ready));
          Timer(const Duration(milliseconds: 30), () {
            events.add(ProviderEvent(type: ProviderEventType.ready));
          });
        }, ProviderEventType.ready),
      );
      clock.elapse(const Duration(milliseconds: 200));
      expect(result.error, isA<TestFailure>());
      expect(events.hasListener, isFalse);
      unawaited(events.close());
    });
  });

  test('C13 rejects a wrong terminal event', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final result = Outcome(
        expectProviderTransition(events.stream, () async {
          events.add(ProviderEvent(type: ProviderEventType.error));
        }, ProviderEventType.ready),
      );
      clock.elapse(const Duration(milliseconds: 200));
      expect(result.error, isA<TestFailure>());
      unawaited(events.close());
    });
  });

  test('C13 times out when the terminal event is missing', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final result = Outcome(
        expectProviderTransition(events.stream, () async {
          events.add(ProviderEvent(type: ProviderEventType.reconciling));
        }, ProviderEventType.ready),
      );
      clock.elapse(const Duration(seconds: 3));
      expect(result.error, isA<TimeoutException>());
      expect(events.hasListener, isFalse);
      expect(clock.pendingTimers, isEmpty);
      unawaited(events.close());
    });
  });

  for (final illegalEvent in [false, true]) {
    test(
      'C11 ${illegalEvent ? 'rejects delayed event' : 'accepts silence'}',
      () {
        fakeAsync((clock) {
          final events = StreamController<ProviderEvent>(
            sync: true,
            onCancel: () async {},
          );
          final result = Outcome(
            expectNoProviderEvents(events.stream, () async {
              if (illegalEvent) {
                Timer(const Duration(milliseconds: 30), () {
                  events.add(ProviderEvent(type: ProviderEventType.ready));
                });
              }
            }),
          );
          clock.elapse(const Duration(milliseconds: 200));
          expect(result.done, isTrue);
          expect(result.error, illegalEvent ? isA<TestFailure>() : isNull);
          expect(events.hasListener, isFalse);
          expect(clock.pendingTimers, isEmpty);
          unawaited(events.close());
        });
      },
    );
  }

  test('nonterminal events extend the quiet interval without failing C13', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final result = Outcome(
        expectProviderTransition(events.stream, () async {
          events.add(ProviderEvent(type: ProviderEventType.ready));
          Timer(const Duration(milliseconds: 80), () {
            events.add(
              ProviderEvent(type: ProviderEventType.configurationChanged),
            );
          });
        }, ProviderEventType.ready),
      );
      clock.elapse(const Duration(milliseconds: 179));
      expect(result.done, isFalse);
      clock.elapse(const Duration(milliseconds: 1));
      expect(result.done, isTrue);
      expect(result.error, isNull);
      unawaited(events.close());
    });
  });

  test(
    'quiet interval starts after action completion even if event was early',
    () {
      fakeAsync((clock) {
        final events = StreamController<ProviderEvent>(
          sync: true,
          onCancel: () async {},
        );
        final result = Outcome(
          expectProviderTransition(events.stream, () async {
            events.add(ProviderEvent(type: ProviderEventType.ready));
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }, ProviderEventType.ready),
        );
        clock.elapse(const Duration(milliseconds: 299));
        expect(result.done, isFalse);
        clock.elapse(const Duration(milliseconds: 1));
        expect(result.done, isTrue);
        expect(result.error, isNull);
        unawaited(events.close());
      });
    },
  );

  test('continuous events cannot extend the overall deadline', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final noise = Timer.periodic(const Duration(milliseconds: 50), (_) {
        events.add(ProviderEvent(type: ProviderEventType.configurationChanged));
      });
      final result = Outcome(
        expectNoProviderEvents(events.stream, () async {}),
      );
      clock.elapse(const Duration(seconds: 3));
      expect(result.error, isA<TimeoutException>());
      expect(events.hasListener, isFalse);
      noise.cancel();
      expect(clock.pendingTimers, isEmpty);
      unawaited(events.close());
    });
  });

  test('late action failure after timeout remains handled', () {
    fakeAsync((clock) {
      final events = StreamController<ProviderEvent>(
        sync: true,
        onCancel: () async {},
      );
      final action = Completer<void>();
      final result = Outcome(
        expectNoProviderEvents(events.stream, () => action.future),
      );
      clock.elapse(const Duration(seconds: 3));
      expect(result.error, isA<TimeoutException>());
      action.completeError(StateError('late failure'));
      clock.flushMicrotasks();
      expect(events.hasListener, isFalse);
      expect(clock.pendingTimers, isEmpty);
      unawaited(events.close());
    });
  });

  test('synchronous action and asynchronous stream errors are propagated', () {
    for (final streamError in [false, true]) {
      fakeAsync((clock) {
        final events = StreamController<ProviderEvent>(
          sync: true,
          onCancel: () async {},
        );
        final error = StateError('controlled failure');
        final result = Outcome(
          expectNoProviderEvents(events.stream, () {
            if (!streamError) throw error;
            scheduleMicrotask(() => events.addError(error));
            return Future<void>.value();
          }),
        );
        clock.flushMicrotasks();
        expect(result.error, same(error));
        expect(events.hasListener, isFalse);
        expect(clock.pendingTimers, isEmpty);
        unawaited(events.close());
      });
    }
  });
}
