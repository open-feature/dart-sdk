import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

void main() {
  test('server releases are scoped to the nested server package', () {
    final config =
        jsonDecode(File('release-please-config.json').readAsStringSync())
            as Map<String, Object?>;
    final packages = config['packages']! as Map<String, Object?>;
    final serverConfig =
        packages['packages/openfeature_dart_server_sdk']!
            as Map<String, Object?>;
    final manifest =
        jsonDecode(File('.release-please-manifest.json').readAsStringSync())
            as Map<String, Object?>;

    expect(packages, isNot(contains('.')));
    expect(serverConfig['release-type'], 'dart');
    expect(serverConfig['component'], 'openfeature_dart_server_sdk');
    expect(serverConfig['package-name'], 'openfeature_dart_server_sdk');
    expect(serverConfig['include-component-in-tag'], isFalse);
    final serverPubspec = File(
      'packages/openfeature_dart_server_sdk/pubspec.yaml',
    ).readAsStringSync();
    final serverVersion =
        manifest['packages/openfeature_dart_server_sdk']! as String;
    expect(
      serverPubspec,
      contains(
        RegExp('^version: ${RegExp.escape(serverVersion)}\$', multiLine: true),
      ),
    );
    expect(serverPubspec, contains('name: openfeature_dart_server_sdk'));
  });

  test('repository root is tooling-only and publishing uses package paths', () {
    final rootPubspec = File('pubspec.yaml').readAsStringSync();
    final publishWorkflow = File(
      '.github/workflows/publish.yaml',
    ).readAsStringSync();

    expect(rootPubspec, contains('publish_to: none'));
    expect(Directory('lib').existsSync(), isFalse);
    expect(
      Directory('packages/openfeature_dart_server_sdk/lib').existsSync(),
      isTrue,
    );
    expect(
      publishWorkflow,
      contains('directory=packages/openfeature_dart_server_sdk'),
    );
    expect(
      publishWorkflow,
      contains('directory=packages/openfeature_dart_client_sdk'),
    );
    expect(publishWorkflow, contains('dart tool/validate_publish_tag.dart'));
    expect(
      publishWorkflow,
      contains(r'openfeature_dart_client_sdk-v[0-9]+.[0-9]+.[0-9]+\+*'),
    );
    expect(
      publishWorkflow,
      isNot(contains("'openfeature_dart_client_sdk-v*'")),
    );
  });

  test('the legacy stable check name aggregates the current test matrix', () {
    final testWorkflow = File(
      '.github/workflows/pr-test.yaml',
    ).readAsStringSync();

    expect(testWorkflow, contains('name: test (ubuntu-latest, stable)'));
    expect(testWorkflow, contains('needs: test'));
    expect(testWorkflow, contains('MATRIX_RESULT:'));
    expect(testWorkflow, contains('needs.test.result'));
    expect(testWorkflow, contains('  merge_group:'));
    final requiredJob = testWorkflow
        .split('  stable-required:')
        .last
        .split('  minimum-dependencies:')
        .first;
    expect(
      requiredJob,
      contains('dart test test/release_please_config_test.dart'),
      reason: 'Milestone validation must run inside the required queue check.',
    );
  });

  test(
    'client non-beta releases retain suffix-safe generic version updates',
    () {
      final config =
          jsonDecode(File('release-please-config.json').readAsStringSync())
              as Map<String, Object?>;
      final packages = config['packages']! as Map<String, Object?>;
      final clientConfig =
          packages['packages/openfeature_dart_client_sdk']!
              as Map<String, Object?>;

      expect(clientConfig['release-type'], 'simple');
      expect(clientConfig['component'], 'openfeature_dart_client_sdk');
      expect(clientConfig['package-name'], 'openfeature_dart_client_sdk');
      expect(clientConfig['version-file'], '.release-please-version');
      expect(clientConfig['extra-files'], [
        {'type': 'generic', 'path': 'pubspec.yaml'},
        {'type': 'generic', 'path': 'README.md'},
      ]);
      expect(clientConfig['prerelease'], isFalse);
      expect(clientConfig, isNot(contains('prerelease-type')));
      expect(clientConfig, isNot(contains('versioning')));
      expect(config['separate-pull-requests'], isTrue);
      expect(clientConfig['draft-pull-request'], isTrue);

      final versionFile = File(
        'packages/openfeature_dart_client_sdk/.release-please-version',
      ).readAsStringSync().trim();
      final pubspec = File(
        'packages/openfeature_dart_client_sdk/pubspec.yaml',
      ).readAsStringSync();
      expect(
        pubspec,
        contains('version: $versionFile # x-release-please-version'),
      );
    },
  );

  test('one-time milestone overrides cannot survive their release manifests', () {
    final config =
        jsonDecode(File('release-please-config.json').readAsStringSync())
            as Map<String, Object?>;
    final packages = config['packages']! as Map<String, Object?>;
    final clientConfig =
        packages['packages/openfeature_dart_client_sdk']!
            as Map<String, Object?>;
    final manifest =
        jsonDecode(File('.release-please-manifest.json').readAsStringSync())
            as Map<String, Object?>;
    final clientVersion =
        manifest['packages/openfeature_dart_client_sdk']! as String;

    expect(clientConfig['release-as'], anyOf(isNull, '0.0.1'));
    expect(
      _isPendingOverride(clientVersion, clientConfig['release-as']),
      isTrue,
      reason:
          'Remove the client milestone override in its generated '
          '0.0.1 release PR before marking it ready; later releases must not be pinned.',
    );
    final serverConfig =
        packages['packages/openfeature_dart_server_sdk']!
            as Map<String, Object?>;
    final serverVersion =
        manifest['packages/openfeature_dart_server_sdk']! as String;
    expect(serverConfig['release-as'], anyOf(isNull, '0.1.0'));
    expect(
      _isPendingOverride(serverVersion, serverConfig['release-as']),
      isTrue,
      reason:
          'Remove the server milestone override in its generated '
          '0.1.0 release PR before marking it ready; later releases must not be pinned.',
    );
    expect(serverConfig['draft-pull-request'], isTrue);
  });

  for (final (current, override, valid) in <(String, String?, bool)>[
    ('0.0.27', '0.1.0', true),
    ('0.0.28', '0.1.0', true),
    ('0.1.0-rc.1', '0.1.0', true),
    ('0.1.0', '0.1.0', false),
    ('0.1.1', '0.1.0', false),
    ('0.0.1-beta.2', '0.0.1', true),
    ('0.0.1-beta.3', '0.0.1', true),
    ('0.0.1', '0.0.1', false),
    ('0.0.2', '0.0.1', false),
    ('0.1.0', null, true),
    ('0.0.1', null, true),
  ]) {
    test('pending override $override at $current is valid=$valid', () {
      expect(_isPendingOverride(current, override), valid);
    });
  }

  test('release changelogs have a single Release Please owner', () {
    final manifest =
        jsonDecode(File('.release-please-manifest.json').readAsStringSync())
            as Map<String, Object?>;
    final clientVersion =
        manifest['packages/openfeature_dart_client_sdk']! as String;
    final clientChangelog = File(
      'packages/openfeature_dart_client_sdk/CHANGELOG.md',
    ).readAsStringSync();
    final serverChangelog = File(
      'packages/openfeature_dart_server_sdk/CHANGELOG.md',
    ).readAsStringSync();
    final clientBetaHeadings = RegExp(
      r'^## \[?0\.0\.1-beta\.1\]?',
      multiLine: true,
    ).allMatches(clientChangelog);

    if (clientVersion == '0.0.0') {
      expect(
        clientChangelog.trim(),
        '<!-- Release Please will generate the 0.0.1-beta.1 entry. -->',
        reason:
            'The bootstrap marker keeps pub validation warning-free while '
            'Release Please creates the first visible changelog entry.',
      );
    } else {
      expect(clientBetaHeadings, hasLength(1));
    }
    expect(
      serverChangelog,
      isNot(contains(RegExp(r'^## Unreleased$', multiLine: true))),
      reason:
          'Release Please inserts generated versions before numeric headings '
          'and does not consume an Unreleased block.',
    );
  });
}

bool _isPendingOverride(String current, Object? override) =>
    override == null ||
    (override is String && Version.parse(current) < Version.parse(override));
