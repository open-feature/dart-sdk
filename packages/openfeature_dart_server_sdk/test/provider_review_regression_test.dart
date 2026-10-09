import 'dart:async';
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/provider_lifecycle.dart';
import 'package:test/test.dart';
import 'provider_capabilities_test.dart'
    show MinimalProvider, LifecycleProvider;

class IdempotentProvider extends LifecycleProvider {
  bool released = false;
  @override
  Future<void> shutdownProvider() async {
    if (released) return;
    released = true;
    await super.shutdownProvider();
  }
}

class HeldFailureProvider extends LifecycleProvider {
  final emitted = Completer<void>();
  final release = Completer<void>();
  bool finished = false;
  @override
  Future<void> initializeProvider(
    EvaluationContext context, {
    String? domain,
  }) async {
    try {
      controller.add(
        ProviderLifecycleEvent(
          ProviderLifecycleEventType.PROVIDER_ERROR,
          'controlled initialization error',
          errorCode: ErrorCode.GENERAL,
        ),
      );
      emitted.complete();
      await release.future;
      throw const ProviderException(
        'controlled initialization error',
        code: ErrorCode.GENERAL,
      );
    } finally {
      finished = true;
    }
  }
}

void main() {
  test(
    '2.2.4 / 2.2.8.1 / 2.2.9 / 2.3.2 new Provider preserves typed success fields',
    () async {
      final provider = MinimalProvider();
      final FlagEvaluationResult<bool> boolean = await provider.getBooleanFlag(
        'b',
        false,
      );
      final FlagEvaluationResult<int> integer = await provider.getIntegerFlag(
        'i',
        0,
      );
      final FlagEvaluationResult<double> floating = await provider
          .getDoubleFlag('d', 0);
      final FlagEvaluationResult<String> string = await provider.getStringFlag(
        's',
        '',
      );
      final FlagEvaluationResult<Map<String, dynamic>> structure =
          await provider.getObjectFlag('o', {});
      expect(
        [
          boolean.value,
          integer.value,
          floating.value,
          string.value,
          structure.value,
        ],
        [
          true,
          42,
          1.5,
          'resolved',
          {'resolved': true},
        ],
      );
      for (final result in <FlagEvaluationResult<dynamic>>[
        boolean,
        integer,
        floating,
        string,
        structure,
      ]) {
        expect(result.variant, 'resolved');
        expect(result.flagMetadata, {'fixture': 'minimal'});
        expect(result.errorCode, isNull);
        expect(result.errorMessage, isNull);
      }
    },
  );

  test(
    '2.5.3 direct capability provider shutdown releases its resource once',
    () async {
      final provider = IdempotentProvider();
      try {
        await provider.initializeProvider(EvaluationContext.immutable());
        await Future.wait([
          provider.shutdownProvider(),
          provider.shutdownProvider(),
        ]);
        await provider.shutdownProvider();
        expect(provider.released, isTrue);
        expect(provider.shutdowns, 1);
      } finally {
        await provider.controller.close();
      }
    },
  );

  test(
    '2.8.1 / 5.3.1 provider-emitted READY STALE READY reaches handlers',
    () async {
      final api = OpenFeatureAPI.isolated();
      final provider = LifecycleProvider();
      final states = <ProviderState>[];
      try {
        api.addEventHandler(
          ProviderLifecycleEventType.PROVIDER_READY,
          (_) => states.add(api.providerStatus),
        );
        api.addEventHandler(
          ProviderLifecycleEventType.PROVIDER_STALE,
          (_) => states.add(api.providerStatus),
        );
        await api.setProviderAndWait(provider);
        states
            .clear(); // Ignore the default provider's ready replay/initialization.
        provider.controller.add(
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_STALE,
            'transport lost',
          ),
        );
        provider.controller.add(
          ProviderLifecycleEvent(
            ProviderLifecycleEventType.PROVIDER_READY,
            'transport recovered',
          ),
        );
        expect(states, [ProviderState.STALE, ProviderState.READY]);
      } finally {
        await api.dispose();
        await provider.controller.close();
      }
    },
  );

  test(
    '2.8.3 provider error handler runs before initialization terminates',
    () async {
      final api = OpenFeatureAPI.isolated();
      final provider = HeldFailureProvider();
      final finishedInHandler = <bool>[];
      api.addEventHandler(
        ProviderLifecycleEventType.PROVIDER_ERROR,
        (_) => finishedInHandler.add(provider.finished),
      );
      final initialization = api.setProviderAndWait(provider);
      final assertion = expectLater(
        initialization,
        throwsA(isA<ProviderException>()),
      );
      try {
        await provider.emitted.future;
        expect(finishedInHandler, [false]);
        provider.release.complete();
        await assertion;
        expect(provider.finished, isTrue);
      } finally {
        if (!provider.release.isCompleted) provider.release.complete();
        await api.dispose();
        await provider.controller.close();
      }
    },
  );
}
