import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../model/bin_io.dart';
import '../model/cch.dart';
import '../model/graph_builder.dart';
import '../model/region.dart';
import '../model/road_tile.dart';

/// Weekly road tiles built by the free buddy-maps GitHub Action (see that repo's README).
/// Override for testing with `--dart-define=BUDDY_MAPS_BASE=http://…`.
const mapsBase = String.fromEnvironment('BUDDY_MAPS_BASE', defaultValue: 'https://github.com/raghavpatpatia/buddy-maps/releases/download/india');
const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)'};

/// Biggest area one download may cover (Google Maps' offline limit).
const maxAreaKm2 = 120000.0;

/// How many junctions this phone can prepare right now: half its free memory, at ~1.2 KB per junction at the peak
/// of the preparation (measured on Delhi: 320k junctions). Delhi ≈ 320k, Bengaluru ≈ 230k.
Future<int> junctionBudget() async {
  try {
    final kb = int.parse(RegExp(r'MemAvailable:\s+(\d+)').firstMatch(await File('/proc/meminfo').readAsString())!.group(1)!);
    return (kb * 1024 * 0.5 / 1200).round().clamp(300000, 2500000);
  } catch (_) {
    return 600000;
  }
}

/// Progress of an area download.
class DownloadStep {
  final String label;

  /// 0..1, or null while a step has no measurable progress.
  final double? fraction;
  const DownloadStep(this.label, [this.fraction]);
}

/// Talks to the map server: the manifest, tile downloads, and building the on-phone map file.
class TileApi {
  static Future<MapManifest> manifest() async {
    final res = await http.get(Uri.parse('$mapsBase/manifest.json'), headers: _ua).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw HttpException('Map server unavailable (${res.statusCode})');
    final m = MapManifest.fromJson(jsonDecode(res.body) as Map);
    if (m.format != 1) throw const FormatException('This map needs a newer version of Buddy');
    return m;
  }

  /// Downloads the tiles under [box], then joins them, applies turn rules and builds the CCH in a background
  /// isolate, writing the map to [path]. Tiles already downloaded for this build are reused (resume).
  /// Returns (file bytes, junctions, road pieces).
  static Future<(int, int, int)> downloadArea(MapManifest m, (double, double, double, double) box, String path, String tileDir,
      void Function(DownloadStep) onStep) async {
    final tiles = m.tilesIn(box);
    if (tiles.isEmpty) throw const FormatException('No map data for this area yet');
    final dir = Directory('$tileDir/${m.built.replaceAll(RegExp(r'[^0-9A-Za-z]'), '')}');
    await dir.create(recursive: true);
    final total = tiles.fold<int>(0, (a, t) => a + m.tiles[t.$1]!.$1);
    var done = 0;
    final client = http.Client();
    try {
      for (final (name, _) in tiles) {
        final f = File('${dir.path}/$name.brt.gz');
        final size = m.tiles[name]!.$1;
        if (!f.existsSync() || f.lengthSync() != size) await _fetch(client, name, f, (n) => onStep(DownloadStep('Downloading roads', (done + n) / total)));
        done += size;
        onStep(DownloadStep('Downloading roads', done / total));
      }
    } finally {
      client.close();
    }
    final rp = ReceivePort();
    final sub = rp.listen((s) => onStep(DownloadStep(s as String)));
    final budget = await junctionBudget();
    try {
      final r = await Isolate.run(_job([for (final (n, _) in tiles) '${dir.path}/$n.brt.gz'], box, path, budget, rp.sendPort));
      await dir.delete(recursive: true);
      return (r[0], r[1], r[2]);
    } finally {
      await sub.cancel();
      rp.close();
    }
  }

  static Future<void> _fetch(http.Client client, String name, File f, void Function(int) onBytes) async {
    Object? last;
    for (var attempt = 0; attempt < 4; attempt++) {
      try {
        final res = await client.send(http.Request('GET', Uri.parse('$mapsBase/$name.brt.gz'))..headers.addAll(_ua));
        if (res.statusCode != 200) throw HttpException('Tile $name: HTTP ${res.statusCode}');
        final part = File('${f.path}.part');
        final sink = part.openWrite();
        var n = 0;
        await for (final chunk in res.stream) {
          sink.add(chunk);
          n += chunk.length;
          onBytes(n);
        }
        await sink.close();
        await part.rename(f.path);
        return;
      } catch (e) {
        last = e;
        await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
    throw last!;
  }

  // Own scope so the isolate closure captures only sendable values.
  static Future<List<int>> Function() _job(List<String> files, (double, double, double, double) box, String path, int budget, SendPort port) =>
      () async {
        final tiles = [for (final f in files) RoadTile.decode(Uint8List.fromList(gzip.decode(await File(f).readAsBytes())))];
        final g = buildGraph(tiles, box, stage: port.send);
        tiles.clear();
        // Checked here, before the memory-hungry step: the manifest only knows roads per whole tile.
        if (g.baseNodes > budget) {
          final pct = (budget / g.baseNodes * 100).floor();
          throw FormatException('This area has ${(g.baseNodes / 1000).round()}k junctions; this phone can prepare about '
              '${(budget / 1000).round()}k right now. Pick an area about $pct% of this size, or close other apps and retry. '
              'Online routing works anywhere without a download.');
        }
        final cch = Cch.build(g, stage: (s) => port.send(switch (s) {
              'Ordering junctions' => 'Preparing fast routing (1/3)',
              'Adding shortcuts' || 'Pruning shortcuts' => 'Preparing fast routing (2/3)',
              _ => 'Preparing fast routing (3/3)',
            }));
        port.send('Saving');
        final w = BinWriter();
        g.write(w);
        cch.write(w);
        final bytes = w.take();
        await File('$path.part').writeAsBytes(bytes, flush: true);
        await File('$path.part').rename(path);
        return [bytes.length, g.baseNodes, g.pieceCount];
      };
}
