import 'dart:async';

import 'package:logging/logging.dart';
import 'package:openfeature_dart_server_sdk/client.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:test/test.dart';

class FailingProvider extends InMemoryProvider {
  FailingProvider() : super({});

  @override
  Future<FlagEvaluationResult<bool>> getBooleanFlag(
    String key,
    bool value, {
    Map<String, dynamic>? context,
  }) async => throw StateError('controlled evaluation failure');
}

void main() {
  test('default evaluation warning can be disabled by named logger', () async {
    final output = <String>[];
    final oldHierarchy = hierarchicalLoggingEnabled;
    final oldRootLevel = Logger.root.level;
    hierarchicalLoggingEnabled = true;
    final oldClientLevel = Logger('FeatureClient').level;
    Logger('FeatureClient').level = null;
    hierarchicalLoggingEnabled = false;
    try {
      await runZoned(
        () async {
          final api = OpenFeatureAPI();
          try {
            await api.setProviderAndWait(FailingProvider());
            final client = api.createClient();
            expect(
              await client.getBooleanValue(
                'missing-before',
                defaultValue: true,
              ),
              isTrue,
            );
            expect(
              output.any(
                (line) =>
                    line.contains('FeatureClient') &&
                    line.contains('missing-before'),
              ),
              isTrue,
            );
            output.clear();
            hierarchicalLoggingEnabled = true;
            Logger('FeatureClient').level = Level.OFF;
            expect(
              await client.getBooleanValue('missing-after', defaultValue: true),
              isTrue,
            );
            expect(
              output.where((line) => line.contains('FeatureClient')),
              isEmpty,
            );
            Logger('unrelated-application').warning('still-visible');
            expect(
              output.any((line) => line.contains('still-visible')),
              isTrue,
            );
          } finally {
            await OpenFeatureAPI.resetInstance();
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) => output.add(line),
        ),
      );
    } finally {
      hierarchicalLoggingEnabled = true;
      Logger('FeatureClient').level = oldClientLevel;
      Logger.root.level = oldRootLevel;
      hierarchicalLoggingEnabled = oldHierarchy;
    }
  });
}
