import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/domain_manager.dart';
import 'package:openfeature_dart_server_sdk/domain.dart';

void main() {
  late DomainManager manager;

  setUp(() {
    manager = DomainManager();
  });

  tearDown(() {
    manager.dispose();
  });

  group('DomainManager', () {
    test('binds client to provider', () {
      manager.bindClientToProvider('client1', 'provider1');
      expect(manager.getProviderForClient('client1'), equals('provider1'));
    });

    test('handles parent-child domain relationships', () {
      manager.bindClientToProvider('parent', 'provider1');

      manager.bindClientToProvider(
        'child',
        'provider2',
        parentDomainId: 'parent',
      );

      final childDomains = manager.getChildDomains('parent');
      expect(childDomains.length, equals(1));
      expect(childDomains.first.clientId, equals('child'));
    });

    test('updates domain settings', () {
      manager.bindClientToProvider('client1', 'provider1');

      final newSettings = {'key': 'value'};
      manager.updateDomainSettings('client1', newSettings);

      final settings = manager.getDomainSettings('client1');
      expect(settings['key'], equals('value'));
    });

    test('throws on invalid configuration', () {
      expect(
        () => manager.bindClientToProvider(
          'client1',
          'provider1',
          config: DomainConfiguration(name: ''),
        ),
        throwsA(isA<DomainValidationException>()),
      );
    });

    test('emits domain updates', () async {
      expect(
        manager.domainUpdates,
        emits(predicate<Domain>((d) => d.clientId == 'client1')),
      );

      manager.bindClientToProvider('client1', 'provider1');
    });
  });
}
