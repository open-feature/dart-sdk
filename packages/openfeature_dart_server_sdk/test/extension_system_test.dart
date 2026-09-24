import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/extension_system.dart';

class TestExtension implements Extension {
  final states = <String>[];
  bool initialized = false;
  bool started = false;

  @override
  ExtensionMetadata get metadata => ExtensionMetadata(
    id: 'test-extension',
    version: '1.0.0',
    author: 'Test Author',
    description: 'Test Extension',
  );

  @override
  Future<void> initialize(ExtensionConfig config) async {
    initialized = true;
    states.add('initialized');
  }

  @override
  Future<void> start() async {
    started = true;
    states.add('started');
  }

  @override
  Future<void> stop() async {
    started = false;
    states.add('stopped');
  }
}

void main() {
  group('ExtensionRegistry', () {
    late ExtensionRegistry registry;
    late TestExtension extension;
    late ExtensionConfig config;

    setUp(() {
      registry = ExtensionRegistry();
      extension = TestExtension();
      config = ExtensionConfig(id: 'test-extension', version: '1.0.0');
    });

    test('registers and initializes extension', () async {
      await registry.register(extension, config);

      expect(extension.initialized, isTrue);
      expect(extension.started, isTrue);
      expect(
        registry.getState('test-extension'),
        equals(ExtensionState.ACTIVE),
      );

      // Clean up
      await registry.unregister('test-extension');
    });

    test('handles extension lifecycle', () async {
      await registry.register(extension, config);

      expect(
        registry.getState('test-extension'),
        equals(ExtensionState.ACTIVE),
      );

      await registry.disableExtension('test-extension');
      expect(extension.started, isFalse);
      expect(
        registry.getState('test-extension'),
        equals(ExtensionState.DISABLED),
      );

      await registry.enableExtension('test-extension');
      expect(extension.started, isTrue);
      expect(
        registry.getState('test-extension'),
        equals(ExtensionState.ACTIVE),
      );

      // Clean up
      await registry.unregister('test-extension');
    });

    test('updates extension config', () async {
      await registry.register(extension, config);

      await registry.updateConfig('test-extension', {'newKey': 'newValue'});
      final updatedConfig = registry.getConfig('test-extension');
      expect(updatedConfig?.settings['newKey'], equals('newValue'));
      expect(extension.states, contains('initialized'));

      // Clean up
      await registry.unregister('test-extension');
    });

    test('unregisters extension', () async {
      await registry.register(extension, config);
      await registry.unregister('test-extension');

      expect(registry.getExtension('test-extension'), isNull);
      expect(extension.started, isFalse);
    });

    test('validates dependencies', () async {
      final dependentConfig = ExtensionConfig(
        id: 'dependent',
        version: '1.0.0',
        dependencies: ['missing-extension'],
      );

      expect(
        () => registry.register(extension, dependentConfig),
        throwsException,
      );
    });

    test('emits events', () async {
      final events = <ExtensionState>[];
      final subscription = registry.events.listen(
        (event) => events.add(event.state),
      );

      await registry.register(extension, config);
      await registry.disableExtension('test-extension');

      // Wait for events to be processed
      await Future.delayed(Duration(milliseconds: 100));

      expect(
        events,
        containsAllInOrder([
          ExtensionState.REGISTERED,
          ExtensionState.LOADING,
          ExtensionState.ACTIVE,
          ExtensionState.DISABLED,
        ]),
      );

      // Clean up
      await subscription.cancel();
      await registry.unregister('test-extension');
    });
  });
}
