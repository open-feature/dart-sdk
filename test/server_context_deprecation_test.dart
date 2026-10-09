import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test(
    'external legacy API gets three migration warnings while modern and const APIs stay clean',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'openfeature-context-warning-',
      );
      final package =
          '${Directory.current.absolute.path}/packages/openfeature_dart_server_sdk';
      try {
        await File('${temporary.path}/pubspec.yaml').writeAsString('''
name: context_warning_consumer
publish_to: none
environment:
  sdk: ^3.12.2
dependencies:
  openfeature_dart_server_sdk:
    path: ${jsonEncode(package)}
''');
        final install = await Process.run(Platform.resolvedExecutable, [
          'pub',
          'get',
        ], workingDirectory: temporary.path);
        expect(
          install.exitCode,
          0,
          reason: '${install.stdout}${install.stderr}',
        );
        final consumer = File('${temporary.path}/consumer.dart');
        await consumer.writeAsString('''
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
void main() {
  final api = OpenFeatureAPI();
  api.setGlobalContext(OpenFeatureEvaluationContext({'region': 'legacy'}));
  assert(api.globalContext?.attributes['region'] == 'legacy');
}
''');
        final legacy = await Process.run(Platform.resolvedExecutable, [
          'analyze',
          '--format=machine',
          '--fatal-infos',
          'consumer.dart',
        ], workingDirectory: temporary.path);
        final diagnostics = '${legacy.stdout}${legacy.stderr}'
            .split('\n')
            .where((line) => line.contains('|DEPRECATED_MEMBER_USE|'));
        expect(
          diagnostics,
          hasLength(3),
          reason: '${legacy.stdout}${legacy.stderr}',
        );
        expect(legacy.exitCode, isNot(0));
        await consumer.writeAsString('''
import 'package:openfeature_dart_server_sdk/evaluation_context.dart';
import 'package:openfeature_dart_server_sdk/open_feature_api.dart';
void main() {
  final api = OpenFeatureAPI();
  api.setEvaluationContext(EvaluationContext.immutable(attributes: {'region': 'modern'}));
  assert(api.evaluationContext?.attributes['region'] == 'modern');
  const retained = EvaluationContext(attributes: {'legacy-default': true});
  assert(retained.attributes['legacy-default'] == true);
}
''');
        final modern = await Process.run(Platform.resolvedExecutable, [
          'analyze',
          '--fatal-infos',
          'consumer.dart',
        ], workingDirectory: temporary.path);
        expect(modern.exitCode, 0, reason: '${modern.stdout}${modern.stderr}');
      } finally {
        // Delete only the new, task-owned temporary consumer directory.
        expect(
          temporary.absolute.parent.path,
          Directory.systemTemp.absolute.path,
        );
        await temporary.delete(recursive: true);
      }
    },
  );
}
