import 'package:flutter/foundation.dart';

/// ChangeNotifier that ignores notifications after dispose, so async work finishing late can't throw.
class SafeNotifier extends ChangeNotifier {
  bool _disposed = false;
  bool get disposed => _disposed;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
