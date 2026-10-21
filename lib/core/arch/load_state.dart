import 'package:flutter/foundation.dart';

import 'safe_notifier.dart';

/// State of an async load (Idle → Loading → Ready | Failed); views switch over it exhaustively.
sealed class LoadState<T> {
  const LoadState();
  T? get data => switch (this) { Ready<T>(:final value) => value, Loading<T>(:final previous) => previous, _ => null };
  bool get isLoading => this is Loading<T>;
}

class Idle<T> extends LoadState<T> {
  const Idle();
}

class Loading<T> extends LoadState<T> {
  final T? previous;
  const Loading([this.previous]);
}

class Ready<T> extends LoadState<T> {
  final T value;
  const Ready(this.value);
}

class Failed<T> extends LoadState<T> {
  final String message;
  final T? previous;
  const Failed(this.message, [this.previous]);
}

/// Controller base for a screen that loads one thing; a newer load always wins over an older one.
abstract class AsyncController<T> extends SafeNotifier {
  LoadState<T> _state = const Idle();
  LoadState<T> get state => _state;
  int _ticket = 0;

  @protected
  set state(LoadState<T> s) {
    _state = s;
    notifyListeners();
  }

  @protected
  Future<void> run(Future<T> Function() load, {required String errorText}) async {
    final ticket = ++_ticket;
    state = Loading(_state.data);
    try {
      final v = await load();
      if (ticket == _ticket) state = Ready(v);
    } catch (e) {
      debugPrint('[$runtimeType] $e');
      if (ticket == _ticket) state = Failed(errorText, _state.data);
    }
  }
}
