import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/shutdown_manager.dart';

void main() {
  group('ShutdownManager', () {
    test('executes hooks in order', () async {
      final executionOrder = <String>[];
      final manager = ShutdownManager();

      manager.registerHook(
        ShutdownHook(
          name: 'hook1',
          phase: ShutdownPhase.PRE_SHUTDOWN,
          execute: () async => executionOrder.add('hook1'),
        ),
      );

      manager.registerHook(
        ShutdownHook(
          name: 'hook2',
          phase: ShutdownPhase.PROVIDER_SHUTDOWN,
          execute: () async => executionOrder.add('hook2'),
        ),
      );

      await manager.shutdown();
      expect(executionOrder, equals(['hook1', 'hook2']));
    });

    test('handles hook timeout', () async {
      final manager = ShutdownManager();

      manager.registerHook(
        ShutdownHook(
          name: 'slow-hook',
          phase: ShutdownPhase.PRE_SHUTDOWN,
          timeout: Duration(milliseconds: 100),
          execute: () => Future.delayed(Duration(milliseconds: 200)),
        ),
      );

      expect(manager.shutdown(), throwsA(isA<ShutdownError>()));
    });

    test('emergency shutdown executes only critical hooks', () async {
      final manager = ShutdownManager();
      final executionOrder = <String>[];

      manager.registerHook(
        ShutdownHook(
          name: 'normal',
          phase: ShutdownPhase.PRE_SHUTDOWN,
          execute: () async => executionOrder.add('normal'),
        ),
      );

      manager.registerHook(
        ShutdownHook(
          name: 'critical',
          phase: ShutdownPhase.PRE_SHUTDOWN,
          critical: true,
          execute: () async => executionOrder.add('critical'),
        ),
      );

      await manager.emergencyShutdown();
      expect(executionOrder, equals(['critical']));
    });

    test('prevents hook registration during shutdown', () async {
      final manager = ShutdownManager();

      manager.registerHook(
        ShutdownHook(
          name: 'initial-hook',
          phase: ShutdownPhase.PRE_SHUTDOWN,
          execute: () async {},
        ),
      );

      // Start shutdown
      final shutdownFuture = manager.shutdown();

      expect(
        () => manager.registerHook(
          ShutdownHook(
            name: 'late-hook',
            phase: ShutdownPhase.PRE_SHUTDOWN,
            execute: () async {},
          ),
        ),
        throwsStateError,
      );

      await shutdownFuture;
    });

    test('emits shutdown events', () async {
      final manager = ShutdownManager();
      final phases = <ShutdownPhase>[];
      final subscription = manager.shutdownEvents.listen(phases.add);

      // Register hooks for all phases
      for (final phase in ShutdownPhase.values) {
        manager.registerHook(
          ShutdownHook(
            name: 'hook-${phase.name}',
            phase: phase,
            execute: () async {},
          ),
        );
      }

      await manager.shutdown();
      await subscription.cancel();
      expect(phases, containsAllInOrder(ShutdownPhase.values));
    });
  });
}
