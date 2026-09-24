import 'dart:async';

import 'package:logging/logging.dart';

import '../feature_provider.dart';
import '../open_feature_event.dart';

/// One routing point for typed handlers and compatibility streams.
class EventDispatcher {
  final _scopes = <EventScope>[];
  bool _closed = false;

  EventScope scope({
    FeatureProvider Function()? provider,
    String? domain,
    bool legacyMetadataMatching = false,
    required Iterable<OpenFeatureEvent> Function(OpenFeatureEventType) current,
  }) {
    final scope = EventScope._(
      this,
      provider,
      domain,
      current,
      legacyMetadataMatching,
    );
    if (_closed) throw StateError('Event dispatcher is closed.');
    _scopes.add(scope);
    return scope;
  }

  void emit(
    OpenFeatureEvent event, {
    bool clientsOnly = false,
    bool Function(String)? domains,
  }) {
    if (_closed) return;
    // Capture routing before any user callback can change a binding.
    final recipients = _scopes.where((scope) {
      if (scope._closed) return false;
      if (scope._provider == null) return !clientsOnly;
      if (domains != null && !domains(scope._domain!)) return false;
      if (event.domain != null && event.domain != scope._domain) return false;
      return event.provider == null
          ? event.providerMetadata == null ||
                (scope._legacyMetadataMatching &&
                    event.providerName == scope._provider().metadata.name)
          : identical(event.provider, scope._provider());
    }).toList();
    final deliveries = [
      for (final scope in recipients)
        (scope, List<EventHandler>.of(scope._handlers[event.type] ?? [])),
    ];
    for (final (scope, handlers) in deliveries) {
      scope._deliver(event, handlers);
    }
  }

  Future<void> close() async {
    _closed = true;
    await Future.wait(_scopes.toList().map((scope) => scope.close()));
  }
}

/// An API or client view of the shared dispatcher, not a second event bus.
class EventScope {
  static final _logger = Logger('OpenFeatureEvents');
  final EventDispatcher _dispatcher;
  final FeatureProvider Function()? _provider;
  final String? _domain;
  final bool _legacyMetadataMatching;
  final Iterable<OpenFeatureEvent> Function(OpenFeatureEventType) _current;
  final _handlers = <OpenFeatureEventType, List<EventHandler>>{};
  final _stream = StreamController<OpenFeatureEvent>.broadcast();
  bool _closed = false;

  EventScope._(
    this._dispatcher,
    this._provider,
    this._domain,
    this._current,
    this._legacyMetadataMatching,
  );

  Stream<OpenFeatureEvent> get events => _stream.stream;

  void add(OpenFeatureEventType type, EventHandler handler) {
    if (_closed) throw StateError('Event scope is closed.');
    final handlers = _handlers.putIfAbsent(type, () => []);
    if (handlers.contains(handler)) return;
    handlers.add(handler);
    for (final event in _current(type).toList()) {
      if (!_closed && handlers.contains(handler)) _invoke(handler, event);
    }
  }

  void remove(OpenFeatureEventType type, EventHandler handler) =>
      _handlers[type]?.remove(handler);

  void _deliver(OpenFeatureEvent event, List<EventHandler> handlers) {
    if (_closed) return;
    _stream.add(event);
    // SDK-only context/binding notifications remain on the legacy stream.
    if (event.provider == null) return;
    for (final handler in handlers) {
      if (!_closed && (_handlers[event.type]?.contains(handler) ?? false)) {
        _invoke(handler, event);
      }
    }
  }

  static void _invoke(EventHandler handler, OpenFeatureEvent event) {
    unawaited(
      Future<void>.sync(() => handler(event)).catchError((
        Object error,
        StackTrace stack,
      ) {
        _logger.warning('Event handler failed', error, stack);
      }),
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _handlers.clear();
    _dispatcher._scopes.remove(this);
    await _stream.close();
  }
}
