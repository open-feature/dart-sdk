import 'package:test/test.dart';
import 'package:openfeature_dart_server_sdk/event_system.dart';

void main() {
  group('OpenFeatureEvent', () {
    test('creates event with correct properties', () {
      final event = OpenFeatureEvent(
        id: 'test-1',
        type: OpenFeatureEventType.flagEvaluated,
        data: {'flag': 'test-flag'},
      );

      expect(event.id, equals('test-1'));
      expect(event.type, equals(OpenFeatureEventType.flagEvaluated));
      expect(event.priority, equals(EventPriority.normal));
      expect(event.data['flag'], equals('test-flag'));
    });

    test('converts to JSON correctly', () {
      final event = OpenFeatureEvent(
        id: 'test-1',
        type: OpenFeatureEventType.flagEvaluated,
        data: {'flag': 'test-flag'},
        priority: EventPriority.high,
      );

      final json = event.toJson();
      expect(json['id'], equals('test-1'));
      expect(json['type'], equals('flagEvaluated'));
      expect(json['priority'], equals('high'));
      expect(json['data']['flag'], equals('test-flag'));
    });
  });

  group('EventFilter', () {
    test('matches event based on type', () {
      final filter = EventFilter(types: {OpenFeatureEventType.flagEvaluated});

      final matchingEvent = OpenFeatureEvent(
        id: 'test-1',
        type: OpenFeatureEventType.flagEvaluated,
        data: {},
      );

      final nonMatchingEvent = OpenFeatureEvent(
        id: 'test-2',
        type: OpenFeatureEventType.error,
        data: {},
      );

      expect(filter.matches(matchingEvent), isTrue);
      expect(filter.matches(nonMatchingEvent), isFalse);
    });

    test('matches event based on priority', () {
      final filter = EventFilter(
        priorities: {EventPriority.high, EventPriority.critical},
      );

      final matchingEvent = OpenFeatureEvent(
        id: 'test-1',
        type: OpenFeatureEventType.flagEvaluated,
        data: {},
        priority: EventPriority.high,
      );

      final nonMatchingEvent = OpenFeatureEvent(
        id: 'test-2',
        type: OpenFeatureEventType.flagEvaluated,
        data: {},
        priority: EventPriority.low,
      );

      expect(filter.matches(matchingEvent), isTrue);
      expect(filter.matches(nonMatchingEvent), isFalse);
    });
  });

  group('EventBus', () {
    late EventBus eventBus;

    setUp(() {
      eventBus = EventBus(maxQueueSize: 2);
    });

    tearDown(() async {
      await eventBus.dispose();
    });

    test('publishes events to subscribers', () async {
      final events = [];
      eventBus.subscribe((event) => events.add(event));

      final testEvent = OpenFeatureEvent(
        id: 'test-1',
        type: OpenFeatureEventType.flagEvaluated,
        data: {},
      );

      eventBus.publish(testEvent);
      await Future.delayed(Duration.zero);

      expect(events.length, equals(1));
      expect(events.first.id, equals('test-1'));
    });

    test('respects max queue size', () {
      eventBus.publish(
        OpenFeatureEvent(
          id: '1',
          type: OpenFeatureEventType.flagEvaluated,
          data: {},
        ),
      );
      eventBus.publish(
        OpenFeatureEvent(
          id: '2',
          type: OpenFeatureEventType.flagEvaluated,
          data: {},
        ),
      );
      eventBus.publish(
        OpenFeatureEvent(
          id: '3',
          type: OpenFeatureEventType.flagEvaluated,
          data: {},
        ),
      );

      final history = eventBus.getEventHistory();
      expect(history.length, equals(2));
      expect(history.first.id, equals('2'));
      expect(history.last.id, equals('3'));
    });

    test('unsubscribe stops event delivery', () async {
      final events = [];
      final subId = eventBus.subscribe((event) => events.add(event));

      eventBus.publish(
        OpenFeatureEvent(
          id: 'test-1',
          type: OpenFeatureEventType.flagEvaluated,
          data: {},
        ),
      );

      await Future.delayed(Duration.zero);
      eventBus.unsubscribe(subId);

      eventBus.publish(
        OpenFeatureEvent(
          id: 'test-2',
          type: OpenFeatureEventType.flagEvaluated,
          data: {},
        ),
      );

      await Future.delayed(Duration.zero);
      expect(events.length, equals(1));
    });
  });
}
