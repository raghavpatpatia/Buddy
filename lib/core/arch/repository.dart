import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Converts a model to and from its stored JSON form.
class JsonCodec<T> {
  final Object Function(T) encode;
  final T Function(dynamic) decode;
  const JsonCodec({required this.encode, required this.decode});
}

/// Stored collection of [T] keyed by [K]; notifies listeners after every write.
abstract interface class Repository<K, T> implements Listenable {
  Iterable<T> get all;
  T? operator [](K id);
  bool contains(K id);
  int get length;
  Future<void> put(T item);
  Future<void> putAll(Iterable<T> items);
  Future<void> remove(K id);

  /// Re-reads storage (another isolate, e.g. a background job, may have written).
  Future<void> reload();
}

/// [Repository] saved as one JSON list in SharedPreferences, with O(1) lookups by id.
class PrefsRepository<K, T> extends ChangeNotifier implements Repository<K, T> {
  final SharedPreferences _prefs;
  final String _key;
  final JsonCodec<T> _codec;
  final K Function(T) _idOf;
  Map<K, T>? _cache;
  Map<K, T> get _items => _cache ??= _load();

  PrefsRepository(this._prefs, this._key, this._codec, this._idOf);

  Map<K, T> _load() {
    final map = <K, T>{};
    for (final e in (jsonDecode(_prefs.getString(_key) ?? '[]') as List)) {
      final item = _codec.decode(e);
      map[_idOf(item)] = item;
    }
    return map;
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode([for (final t in _items.values) _codec.encode(t)]));
    notifyListeners();
  }

  @override
  Iterable<T> get all => _items.values;
  @override
  T? operator [](K id) => _items[id];
  @override
  bool contains(K id) => _items.containsKey(id);
  @override
  int get length => _items.length;

  @override
  Future<void> put(T item) {
    _items[_idOf(item)] = item;
    return _save();
  }

  @override
  Future<void> putAll(Iterable<T> items) {
    for (final t in items) {
      _items[_idOf(t)] = t;
    }
    return _save();
  }

  @override
  Future<void> remove(K id) {
    _items.remove(id);
    return _save();
  }

  @override
  Future<void> reload() async {
    await _prefs.reload();
    _cache = null;
    notifyListeners();
  }
}
