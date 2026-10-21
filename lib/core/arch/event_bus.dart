import 'dart:async';

/// App-wide observer: features publish typed events and others subscribe without knowing each other.
class EventBus {
  EventBus._();
  static final instance = EventBus._();

  final _controller = StreamController<Object>.broadcast();

  void emit(Object event) => _controller.add(event);

  /// Stream of events of type [E]; cancel the subscription when done.
  Stream<E> on<E>() => _controller.stream.where((e) => e is E).cast<E>();
}

sealed class AppEvent {
  const AppEvent();
}

class MailOpened extends AppEvent {
  final String trackId;
  const MailOpened(this.trackId);
}
