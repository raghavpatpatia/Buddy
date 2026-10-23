import 'dart:convert';
import 'dart:typed_data';

/// Tile layout version this app understands (buddy-maps' tile_format.dart).
const tileFormat = 1;
const _tileMagic = 0x42525431; // "BRT1"

/// One downloaded 1° tile of roads (already gunzipped). See buddy-maps' tile_format.dart for the layout.
class RoadTile {
  final Int64List nodeIds;
  final Int32List lat, lon;
  final Int64List wayIds;
  final Int32List refStart, refs, name;
  final Uint8List kind, speed, flags;
  final Int8List dir;
  final Int32List restrFrom, restrVia, restrTo;
  final Uint8List restrOnly;
  final List<String> names;

  RoadTile._(this.nodeIds, this.lat, this.lon, this.wayIds, this.refStart, this.refs, this.kind, this.speed, this.flags, this.dir,
      this.name, this.restrFrom, this.restrVia, this.restrTo, this.restrOnly, this.names);

  factory RoadTile.decode(Uint8List raw) {
    final b = raw.offsetInBytes % 8 == 0 ? raw : Uint8List.fromList(raw);
    final h = Int32List.sublistView(b, 0, 32);
    if (h[0] != _tileMagic) throw const FormatException('Not a road tile');
    if (h[1] != tileFormat) throw FormatException('Tile format ${h[1]} needs a newer Buddy');
    final n = h[2], w = h[3], refs = h[4], r = h[5], nb = h[7];
    var off = 32;
    T take<T>(int bytes, T Function(int s, int e) make) {
      final v = make(off, off + bytes);
      off += (bytes + 3) & ~3;
      return v;
    }

    Int32List i32(int len) => take(len * 4, (s, e) => Int32List.sublistView(b, s, e));
    Int64List i64(int len) => take(len * 8, (s, e) => Int64List.sublistView(b, s, e));
    Uint8List u8(int len) => take(len, (s, e) => Uint8List.sublistView(b, s, e));

    final ids = i64(n), la = i32(n), lo = i32(n), wids = i64(w), rs = i32(w + 1), rf = i32(refs);
    final k = u8(w), sp = u8(w), fl = u8(w);
    final d = take(w, (s, e) => Int8List.sublistView(b, s, e));
    final nm = i32(w), rFrom = i32(r), rVia = i32(r), rTo = i32(r), rOnly = u8(r);
    final text = utf8.decode(u8(nb));
    return RoadTile._(ids, la, lo, wids, rs, rf, k, sp, fl, d, nm, rFrom, rVia, rTo, rOnly, h[6] == 0 ? [] : text.split('\n'));
  }
}
