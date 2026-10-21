import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/store.dart';
import '../model/brain_model.dart';

/// Where model files live, and resumable downloads of them.
class ModelFiles {
  /// Models can also be copied in by hand (e.g. from a PC over USB) to `Download/BuddyModels/{id}.litertlm`.
  static String sideloadPath(BrainModel m) => '/storage/emulated/0/Download/BuddyModels/${m.id}.litertlm';

  static Future<String> pathFor(BrainModel m) async {
    if (File(sideloadPath(m)).existsSync()) return sideloadPath(m);
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/models');
    await dir.create(recursive: true);
    return '${dir.path}/${m.id}.litertlm';
  }

  /// True when [m] is fully downloaded (or sideloaded).
  static Future<bool> has(BrainModel m) async {
    if (File(sideloadPath(m)).existsSync()) return true;
    final f = File(await pathFor(m));
    return f.existsSync() && Store.raw.getBool('brain_ok_${m.id}') == true;
  }

  /// Downloads [m] with progress (0..1), resuming a partial file; throws on network errors.
  static Future<void> download(BrainModel m, void Function(double) onProgress) async {
    final path = await pathFor(m);
    final part = File('$path.part');
    final have = part.existsSync() ? part.lengthSync() : 0;
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(m.url));
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final res = await client.send(req);
      if (res.statusCode != 200 && res.statusCode != 206) throw HttpException('HTTP ${res.statusCode}');
      final resumed = res.statusCode == 206;
      final total = (res.contentLength ?? 0) + (resumed ? have : 0);
      var got = resumed ? have : 0;
      final sink = part.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) onProgress(got / total);
        }
      } finally {
        await sink.close();
      }
      await part.rename(path);
      await Store.raw.setBool('brain_ok_${m.id}', true);
    } finally {
      client.close();
    }
  }

  static Future<void> delete(BrainModel m) async {
    final p = await pathFor(m);
    for (final f in [File(p), File('$p.part')]) {
      if (f.existsSync()) await f.delete();
    }
    await Store.raw.remove('brain_ok_${m.id}');
  }
}
