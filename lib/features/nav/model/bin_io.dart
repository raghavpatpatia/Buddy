import 'dart:typed_data';

/// Writes typed arrays back to back, each prefixed by its element count and padded to 8 bytes,
/// so they can be read back as zero-copy views.
class BinWriter {
  final _b = BytesBuilder(copy: false);
  int _len = 0;

  void _raw(Uint8List bytes) {
    _b.add(bytes);
    _len += bytes.length;
    final pad = (8 - _len % 8) % 8;
    if (pad > 0) {
      _b.add(Uint8List(pad));
      _len += pad;
    }
  }

  void ints(List<int> v) => _raw(Uint8List.view(Int64List.fromList(v).buffer));

  void array(TypedData t) {
    _raw(Uint8List.view(Int64List.fromList([t.lengthInBytes ~/ t.elementSizeInBytes]).buffer));
    _raw(t.buffer.asUint8List(t.offsetInBytes, t.lengthInBytes));
  }

  Uint8List take() => _b.takeBytes();
}

class BinReader {
  final Uint8List b;
  int _pos = 0;
  BinReader(Uint8List raw) : b = raw.offsetInBytes % 8 == 0 ? raw : Uint8List.fromList(raw);

  int _n() {
    final v = Int64List.sublistView(b, _pos, _pos + 8)[0];
    _pos += 8;
    return v;
  }

  List<int> ints(int count) {
    final v = Int64List.sublistView(b, _pos, _pos + count * 8).toList();
    _pos += count * 8;
    return v;
  }

  T _view<T>(int size, T Function(int start, int end) make) {
    final n = _n();
    final start = _pos;
    _pos += n * size;
    final v = make(start, _pos);
    _pos = (_pos + 7) & ~7;
    return v;
  }

  Int32List i32() => _view(4, (s, e) => Int32List.sublistView(b, s, e));
  Int64List i64() => _view(8, (s, e) => Int64List.sublistView(b, s, e));
  Float32List f32() => _view(4, (s, e) => Float32List.sublistView(b, s, e));
  Uint8List u8() => _view(1, (s, e) => Uint8List.sublistView(b, s, e));
}
