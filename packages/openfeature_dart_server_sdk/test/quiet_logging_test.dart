import 'dart:async';
import 'package:logging/logging.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/experimental/isolated.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/hooks.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:test/test.dart';

class FailingProvider extends InMemoryProvider {
  FailingProvider() : super({});
  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool value, {
    Map<String, dynamic>? context,
  }) async => throw StateError('controlled evaluation failure');
  @override
  Future<void> track(
    String name, {
    Map<String, dynamic>? evaluationContext,
    TrackingEventDetails? trackingDetails,
  }) async => throw StateError('controlled tracking failure');
}

void main() {
  for (final singleton in [true, false]) {
    test(
      '${singleton ? 'singleton' : 'isolated'} preserves application logging and is quiet by default',
      () async {
        await OpenFeatureAPI.resetInstance();
        final oldLevel = Logger.root.level;
        final output = <String>[];
        final records = <LogRecord>[];
        Logger.root.level = Level.WARNING;
        final subscription = Logger.root.onRecord.listen(records.add);
        try {
          await runZoned(
            () async {
              final api = singleton
                  ? OpenFeatureAPI()
                  : createIsolatedOpenFeatureAPI();
              try {
                expect(Logger.root.level, Level.WARNING);
                Logger('MyApp.db').fine('application fine record');
                await api.setProviderAndWait(FailingProvider());
                final client = api.createClient();
                final details = await client.getBooleanDetails(
                  'missing',
                  defaultValue: true,
                );
                expect(details.value, isTrue);
                expect(details.errorCode, isNotNull);
                await client.track('controlled-failure');
                expect(
                  records.where((r) => r.loggerName == 'FeatureClient'),
                  isEmpty,
                );
                expect(
                  records.where((r) => r.message == 'application fine record'),
                  isEmpty,
                );
                expect(output, isEmpty);
                Logger('MyApp.db').warning('application warning');
                expect(
                  records.where((r) => r.message == 'application warning'),
                  hasLength(1),
                );
                expect(output, isEmpty);
              } finally {
                await api.dispose();
              }
            },
            zoneSpecification: ZoneSpecification(
              print: (self, parent, zone, line) => output.add(line),
            ),
          );
        } finally {
          await subscription.cancel();
          await OpenFeatureAPI.resetInstance();
          Logger.root.level = oldLevel;
        }
      },
    );
  }
  test(
    '1.4.11 opt-in LoggingHook retains evaluation error diagnostics',
    () async {
      final api = createIsolatedOpenFeatureAPI();
      final messages = <String>[];
      try {
        await api.setProviderAndWait(FailingProvider());
        api.addEvaluationHooks([LoggingHook(logger: messages.add)]);
        final result = await api.createClient().getBooleanDetails(
          'missing',
          defaultValue: true,
        );
        expect(result.value, isTrue);
        expect(result.errorCode, isNotNull);
        expect(messages.any((message) => message.contains('missing')), isTrue);
        expect(
          messages.any(
            (message) => message.contains('controlled evaluation failure'),
          ),
          isTrue,
        );
      } finally {
        await api.dispose();
      }
    },
  );
}
