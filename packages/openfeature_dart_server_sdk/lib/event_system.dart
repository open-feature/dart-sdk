/// Legacy application telemetry utilities, unrelated to provider lifecycle.
///
/// For SDK provider events use open_feature_event.dart and the API/client
/// addEventHandler/removeEventHandler methods. These standalone utilities are
/// retained for source compatibility only; they are not an SDK event source.
@Deprecated('Use open_feature_event.dart and API/client event handlers.')
library;

import 'dart:async';
import 'dart:collection';

/// Event types supported by the system
enum OpenFeatureEventType {
  flagEvaluated,
  providerChanged,
  contextUpdated,
  configurationChanged,
  error,
  shutdown,
  sync,
  stateChanged,
  providerReconciling,
}

/// Event priority levels
enum EventPriority { low, normal, high, critical }

/// Base event class
class OpenFeatureEvent {
  final String id;
  final OpenFeatureEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> data;
  final EventPriority priority;

  OpenFeatureEvent({
    required this.id,
    required this.type,
    required this.data,
    this.priority = EventPriority.normal,
  }) : timestamp = DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
    'priority': priority.name,
  };
}

/// Event filter specification
class EventFilter {
  final Set<OpenFeatureEventType>? types;
  final Set<EventPriority>? priorities;
  final bool Function(OpenFeatureEvent)? customFilter;

  const EventFilter({this.types, this.priorities, this.customFilter});

  bool matches(OpenFeatureEvent event) {
    if (types != null && !types!.contains(event.type)) return false;
    if (priorities != null && !priorities!.contains(event.priority))
      return false;
    if (customFilter != null && !customFilter!(event)) return false;
    return true;
  }
}

/// Event subscription
class EventSubscription {
  final String id;
  final EventFilter filter;
  final void Function(OpenFeatureEvent) handler;
  final bool autoAck;
  bool _active = true;

  EventSubscription({
    required this.id,
    required this.filter,
    required this.handler,
    this.autoAck = true,
  });

  void cancel() => _active = false;
  bool get isActive => _active;
}

/// Event bus for managing subscriptions and dispatching events
class EventBus {
  final Map<String, EventSubscription> _subscriptions = {};
  final StreamController<OpenFeatureEvent> _controller;
  final int _maxQueueSize;
  final Queue<OpenFeatureEvent> _eventQueue = Queue();

  EventBus({bool sync = false, int maxQueueSize = 1000})
    : _controller = StreamController<OpenFeatureEvent>.broadcast(sync: sync),
      _maxQueueSize = maxQueueSize {
    _controller.stream.listen(_dispatchEvent);
  }

  String subscribe(
    void Function(OpenFeatureEvent) handler, {
    EventFilter? filter,
    bool autoAck = true,
  }) {
    final subscription = EventSubscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      filter: filter ?? const EventFilter(),
      handler: handler,
      autoAck: autoAck,
    );
    _subscriptions[subscription.id] = subscription;
    return subscription.id;
  }

  void unsubscribe(String subscriptionId) {
    final subscription = _subscriptions.remove(subscriptionId);
    if (subscription != null) {
      subscription.cancel();
    }
  }

  void publish(OpenFeatureEvent event) {
    if (_eventQueue.length >= _maxQueueSize) {
      _eventQueue.removeFirst();
    }
    _eventQueue.add(event);
    _controller.add(event);
  }

  void _dispatchEvent(OpenFeatureEvent event) {
    for (final subscription in _subscriptions.values) {
      if (!subscription.isActive) continue;
      if (!subscription.filter.matches(event)) continue;

      try {
        subscription.handler(event);
      } catch (e) {
        print('Error in event handler: $e');
      }
    }
  }

  Stream<OpenFeatureEvent> filterEvents(EventFilter filter) {
    return _controller.stream.where(filter.matches);
  }

  List<OpenFeatureEvent> getEventHistory() {
    return List.unmodifiable(_eventQueue);
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    _subscriptions.clear();
    _eventQueue.clear();
    await _controller.close();
  }
}

/// Global event bus instance
class OpenFeatureEvents {
  static final EventBus _instance = EventBus();
  static EventBus get instance => _instance;
}
