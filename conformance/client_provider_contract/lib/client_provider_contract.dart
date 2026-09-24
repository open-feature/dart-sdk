/// Shared validation contract v1. This development-only package is unpublished.
library;

import 'dart:async';
import 'package:openfeature_dart_client_sdk/openfeature_dart_client_sdk_experimental.dart';
import 'package:test/test.dart';

const clientProviderContractVersion = '1';

/// A provider-owned control boundary. Implement this in the canonical provider
/// repository using its real provider and controlled transport/backend.
/// It must not reimplement the provider inside this harness.
abstract interface class ClientProviderFixture {
  FeatureProvider get provider;
  int get shutdownCalls;

  /// Configure responses for a subject. Null denotes signed-out/anonymous.
  void setFlags(String? subject, Map<String, Object> flags);

  /// Trigger the provider's own configuration refresh and await completion.
  Future<void> refresh();

  /// Make the next initialization or refresh request fail at the transport.
  void failNextRequest();

  /// Hold the next transport response; the handle completes only on release.
  HeldProviderResponse holdNextResponse();

  /// Close provider-owned test transport resources after SDK shutdown.
  Future<void> close();
}

abstract interface class HeldProviderResponse {
  Future<void> get started;
  void release();
}

typedef ClientProviderFixtureFactory =
    FutureOr<ClientProviderFixture> Function();

/// Register the same assertions for every provider. Missing fixture controls or
/// skipped scenarios are incomplete evidence, never a provider pass.
void runClientProviderContract({
  required String providerName,
  required ClientProviderFixtureFactory createFixture,
}) {
  group(
    'client-provider-contract-v$clientProviderContractVersion [$providerName]',
    () {
      late OpenFeatureAPI api;
      late ClientProviderFixture fixture;
      late OpenFeatureClient client;

      setUp(() async {
        api = createIsolatedOpenFeatureAPI(
          lifecycleTimeout: const Duration(seconds: 3),
        );
        fixture = await createFixture();
        fixture.setFlags('a', {
          'boolean': true,
          'integer': 7,
          'double': 1.25,
          'string': 'alpha',
          'structure': <String, Object?>{'enabled': true},
          'identity': 'a',
        });
        fixture.setFlags('b', {'identity': 'b'});
        fixture.setFlags('c', {'identity': 'c'});
        fixture.setFlags(null, {});
        await api.setEvaluationContextAndWait(
          EvaluationContext(targetingKey: 'a'),
        );
        client = api.getClient('shared-contract');
      });
      tearDown(() async {
        try {
          await api.shutdown();
        } finally {
          await fixture.close();
        }
      });

      test('C01 initialization status precedes ready handlers', () async {
        final observed = <ProviderStatus>[];
        client.addHandler(
          ProviderEventType.ready,
          (_) => observed.add(client.providerStatus),
        );
        await api.setProviderAndWait(fixture.provider);
        expect(client.providerStatus, ProviderStatus.ready);
        expect(observed, isNotEmpty);
        expect(
          observed.every((status) => status == ProviderStatus.ready),
          isTrue,
        );
      });

      test(
        'C02 synchronous typed values and details preserve defaults',
        () async {
          await api.setProviderAndWait(fixture.provider);
          // Assignments deliberately fail compilation if evaluation becomes async.
          final bool boolean = client.getBooleanValue('boolean', false);
          final int integer = client.getIntegerValue('integer', 0);
          final double floating = client.getDoubleValue('double', 0);
          final String string = client.getStringValue('string', 'fallback');
          final Map<String, Object?> structure = client.getStructureValue(
            'structure',
            {},
          );
          expect(
            [boolean, integer, floating, string, structure],
            [
              true,
              7,
              1.25,
              'alpha',
              {'enabled': true},
            ],
          );
          final details = client.getBooleanDetails('boolean', false);
          expect(details.flagKey, 'boolean');
          expect(details.value, isTrue);
          expect(details.errorCode, isNull);
          expect(client.getBooleanValue('absent', true), isTrue);
          expect(client.getIntegerValue('absent', 9), 9);
          expect(client.getDoubleValue('absent', 9.5), 9.5);
          expect(client.getStringValue('absent', 'fallback'), 'fallback');
          expect(client.getStructureValue('absent', {'fallback': true}), {
            'fallback': true,
          });
          expect(
            client.getBooleanDetails('string', false).errorCode,
            ErrorCode.typeMismatch,
          );
        },
      );

      test(
        'C03 initialization failure leaves safe defaults and error ordering',
        () async {
          final observed = <ProviderStatus>[];
          client.addHandler(
            ProviderEventType.error,
            (_) => observed.add(client.providerStatus),
          );
          fixture.failNextRequest();
          await expectLater(
            api.setProviderAndWait(fixture.provider),
            throwsA(anything),
          );
          expect(client.getStringValue('identity', 'fallback'), 'fallback');
          expect(observed, isNotEmpty);
          expect(
            observed.every(
              (status) =>
                  status == ProviderStatus.error ||
                  status == ProviderStatus.fatal,
            ),
            isTrue,
          );
        },
      );

      test('C04 configuration refresh reaches existing clients', () async {
        await api.setProviderAndWait(fixture.provider);
        var changed = 0;
        client.addHandler(
          ProviderEventType.configurationChanged,
          (_) => changed++,
        );
        fixture.setFlags('a', {'boolean': false});
        await fixture.refresh();
        await Future<void>.delayed(Duration.zero);
        expect(client.getBooleanValue('boolean', true), isFalse);
        expect(changed, greaterThan(0));
      });

      test('C05 refresh failure is observable and recovery works', () async {
        await api.setProviderAndWait(fixture.provider);
        var errors = 0;
        client.addHandler(ProviderEventType.error, (_) => errors++);
        fixture.failNextRequest();
        try {
          await fixture.refresh();
        } on Object {
          /* Provider may report via event and future. */
        }
        await Future<void>.delayed(Duration.zero);
        expect(errors, greaterThan(0));
        fixture.setFlags('a', {'identity': 'recovered'});
        await fixture.refresh();
        expect(client.getStringValue('identity', 'fallback'), 'recovered');
      });

      test(
        'C06 identity changes and sign-out never return prior identity flags',
        () async {
          await api.setProviderAndWait(fixture.provider);
          expect(client.getStringValue('identity', 'fallback'), 'a');
          await api.setEvaluationContextAndWait(
            EvaluationContext(targetingKey: 'b'),
          );
          expect(client.getStringValue('identity', 'fallback'), 'b');
          try {
            await api.setEvaluationContextAndWait(EvaluationContext.empty);
          } on Object {
            // Providers may reject anonymous identities, but must retire private data.
          }
          expect(client.getStringValue('identity', 'fallback'), 'fallback');
        },
      );

      test(
        'C07 rapid reconciliation ends with the latest requested identity',
        () async {
          await api.setProviderAndWait(fixture.provider);
          final held = fixture.holdNextResponse();
          addTearDown(held.release);
          final first = api.setEvaluationContextAndWait(
            EvaluationContext(targetingKey: 'b'),
          );
          await held.started;
          final second = api.setEvaluationContextAndWait(
            EvaluationContext(targetingKey: 'c'),
          );
          held.release();
          await Future.wait([first, second]);
          expect(client.getStringValue('identity', 'fallback'), 'c');
        },
      );

      test(
        'C08 a stale refresh cannot restore the previous identity',
        () async {
          await api.setProviderAndWait(fixture.provider);
          final held = fixture.holdNextResponse();
          addTearDown(held.release);
          final refresh = fixture.refresh();
          final observedRefresh = refresh.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          );
          await held.started;
          final identityChange = api.setEvaluationContextAndWait(
            EvaluationContext(targetingKey: 'b'),
          );
          held.release();
          await Future.wait([observedRefresh, identityChange]);
          expect(client.getStringValue('identity', 'fallback'), 'b');
        },
      );

      test(
        'C09 replacement ignores late work from the retired provider',
        () async {
          await api.setProviderAndWait(fixture.provider);
          final held = fixture.holdNextResponse();
          addTearDown(held.release);
          final refresh = fixture.refresh().then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {},
          );
          await held.started;
          final replacement = await createFixture();
          addTearDown(replacement.close);
          replacement.setFlags('a', {'identity': 'replacement'});
          await api.setProviderAndWait(replacement.provider);
          held.release();
          await refresh;
          expect(client.getStringValue('identity', 'fallback'), 'replacement');
          expect(fixture.shutdownCalls, 1);
        },
      );

      test('C10 shutdown ignores late refresh and clears state', () async {
        await api.setProviderAndWait(fixture.provider);
        final held = fixture.holdNextResponse();
        addTearDown(held.release);
        final refresh = fixture.refresh().then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {},
        );
        await held.started;
        await api.shutdown();
        held.release();
        await refresh;
        expect(client.providerStatus, ProviderStatus.notReady);
        expect(client.getStringValue('identity', 'fallback'), 'fallback');
        expect(fixture.shutdownCalls, 1);
      });
    },
  );
}
