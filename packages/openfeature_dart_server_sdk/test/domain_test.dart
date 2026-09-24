import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/domain.dart';

void main() {
  group('DomainConfiguration', () {
    test('validates correctly', () {
      final validConfig = DomainConfiguration(name: 'test');
      expect(validConfig.validate(), isTrue);

      final emptyNameConfig = DomainConfiguration(name: '');
      expect(emptyNameConfig.validate(), isFalse);

      final emptyParentConfig = DomainConfiguration(
        name: 'test',
        parentDomain: '',
      );
      expect(emptyParentConfig.validate(), isFalse);
    });

    test('initializes with default values', () {
      final config = DomainConfiguration(name: 'test');
      expect(config.settings, isEmpty);
      expect(config.parentDomain, isNull);
      expect(config.childDomains, isEmpty);
    });
  });

  group('Domain', () {
    test('handles parent-child relationships', () {
      final parentConfig = DomainConfiguration(name: 'parent');
      final parent = Domain('parent-id', 'provider1', config: parentConfig);

      final childConfig = DomainConfiguration(name: 'child');
      final child = Domain(
        'child-id',
        'provider2',
        config: childConfig,
        parent: parent,
      );

      expect(parent.children, contains(child));
      expect(child.isChildOf(parent), isTrue);
    });

    test('merges settings correctly', () {
      final parentConfig = DomainConfiguration(
        name: 'parent',
        settings: {'key1': 'parent', 'shared': 'parent'},
      );
      final parent = Domain('parent-id', 'provider1', config: parentConfig);

      final childConfig = DomainConfiguration(
        name: 'child',
        settings: {'key2': 'child', 'shared': 'child'},
      );
      final child = Domain(
        'child-id',
        'provider2',
        config: childConfig,
        parent: parent,
      );

      final settings = child.effectiveSettings;
      expect(settings['key1'], equals('parent'));
      expect(settings['key2'], equals('child'));
      expect(settings['shared'], equals('child'));
    });
  });
}
