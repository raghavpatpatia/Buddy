/// Bounded cache: keeps the [capacity] most recently used entries, each valid for [ttl].
class LruCache<K, V> {
  final int capacity;
  final Duration ttl;
  final _map = <K, (DateTime, V)>{};
  LruCache({required this.capacity, required this.ttl});

  V? get(K key) {
    final hit = _map.remove(key);
    if (hit == null) return null;
    if (DateTime.now().difference(hit.$1) > ttl) return null;
    _map[key] = hit;
    return hit.$2;
  }

  void put(K key, V value) {
    _map.remove(key);
    _map[key] = (DateTime.now(), value);
    if (_map.length > capacity) _map.remove(_map.keys.first);
  }

  int get length => _map.length;
}
