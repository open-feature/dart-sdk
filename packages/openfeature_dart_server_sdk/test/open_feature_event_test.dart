import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/feature_provider.dart';
import 'package:openfeature_dart_server_sdk/open_feature_event.dart';

void main() {
  group('OpenFeatureEvent', () {
    test('constructs correctly', () {
      final event = OpenFeatureEvent(
        OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED,
        'Configuration changed',
        data: {'flagKey': 'test-flag'},
      );

      expect(
        event.type,
        equals(OpenFeatureEventType.PROVIDER_CONFIGURATION_CHANGED),
      );
      expect(event.message, equals('Configuration changed'));
      expect(event.data['flagKey'], equals('test-flag'));
    });

    test('constructs without data', () {
      final event = OpenFeatureEvent(
        OpenFeatureEventType.PROVIDER_ERROR,
        'Error occurred',
      );

      expect(event.type, equals(OpenFeatureEventType.PROVIDER_ERROR));
      expect(event.message, equals('Error occurred'));
      expect(event.data, isNull);
    });

    test('includes timestamp', () {
      final before = DateTime.now();
      final event = OpenFeatureEvent(
        OpenFeatureEventType.PROVIDER_READY,
        'Provider ready',
      );
      final after = DateTime.now();

      expect(
        event.timestamp.isAfter(before) ||
            event.timestamp.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        event.timestamp.isBefore(after) ||
            event.timestamp.isAtSameMomentAs(after),
        isTrue,
      );
    });

    test('supports provider metadata', () {
      final metadata = ProviderMetadata(name: 'TestProvider');
      final event = OpenFeatureEvent(
        OpenFeatureEventType.PROVIDER_READY,
        'Provider ready',
        providerMetadata: metadata,
      );

      expect(event.providerMetadata, equals(metadata));
      expect(event.providerMetadata?.name, equals('TestProvider'));
    });
  });
}
