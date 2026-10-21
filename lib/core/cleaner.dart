import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'store.dart';

class CleanItem {
  final String path;
  final int size;
  final String note;
  CleanItem(this.path, this.size, [this.note = '']);
  Map<String, dynamic> toJson() => {'p': path, 's': size, 'n': note};
  static CleanItem fromJson(Map m) => CleanItem(m['p'], m['s'], m['n'] ?? '');
}

/// Category id -> (title, explanation, safe-to-preselect)
const cleanCategories = {
  'thumbs': ('Thumbnail cache', 'Gallery previews. Android rebuilds them when needed.', true),
  'apks': ('Old APK installers', 'Installer files in Downloads. The apps stay installed.', true),
  'dupes': ('Duplicate files', 'Exact copies (same size + content fingerprint). The oldest copy is kept.', true),
  'statuses': ('Viewed WhatsApp statuses', 'Cached status videos/photos you already watched.', true),
  'shots': ('Old screenshots (60+ days)', 'Screenshots you probably no longer need. Review first.', false),
  'oldDownloads': ('Old downloads (90+ days)', 'Files sitting in Downloads for 3+ months. Review first.', false),
  'bigVideos': ('Large videos (200 MB+)', 'Biggest space hogs. Review before deleting.', false),
};

/// (path, size in bytes, modified ms since epoch)
typedef FileEntry = (String, int, int);

/// Rule-based on-device storage analyser. Never deletes anything by itself.
class Cleaner {
  static const root = '/storage/emulated/0';
  static const _skipDirs = {'Android/data', 'Android/obb'};

  /// Folders MediaStore skips (.nomedia): thumbnail caches and WhatsApp media (its "Sent" copies are classic duplicates).
  static const _hiddenCaches = [
    'DCIM/.thumbnails', 'Pictures/.thumbnails', 'Movies/.thumbnails', 'Music/.thumbnails',
    'Android/media/com.whatsapp/WhatsApp/Media', 'WhatsApp/Media',
    'Android/media/com.whatsapp.w4b/WhatsApp Business/Media',
  ];

  /// [indexed]: file list from MediaStore (fast path, foreground only). Without it the whole storage is walked.
  /// [onProgress] gets (files checked, current step, bytes found so far) a few times a second.
  static Future<Map<String, List<CleanItem>>> scan({
    List<FileEntry>? indexed,
    void Function(int seen, String step, int found)? onProgress,
  }) async {
    if (onProgress == null) return Isolate.run(_job(indexed, null));
    final rp = ReceivePort();
    final sub = rp.listen((m) {
      final l = m as List;
      onProgress(l[0] as int, l[1] as String, l[2] as int);
    });
    try {
      return await Isolate.run(_job(indexed, rp.sendPort));
    } finally {
      await sub.cancel();
      rp.close();
    }
  }

  /// Builds the isolate entry in its own scope. A closure created inside scan() would share scan()'s
  /// captured variables, including onProgress → the Cleaner screen → decoded thumbnails, which can't be
  /// sent to another isolate ("object is unsendable": the intermittent "Scan failed").
  static Map<String, List<CleanItem>> Function() _job(List<FileEntry>? indexed, SendPort? port) =>
      () => _scanSync(indexed, port);

  static Map<String, List<CleanItem>> _scanSync(List<FileEntry>? indexed, SendPort? progress) {
    final sw = Stopwatch()..start();
    List<FileEntry> entries;
    if (indexed != null) {
      // Merge MediaStore with the walked folders; a file must only count once.
      final byPath = <String, FileEntry>{for (final e in indexed) if (!e.$1.contains('/Android/data/')) e.$1: e};
      for (final e in _walk(_hiddenCaches.map((d) => '$root/$d'), progress)) {
        byPath[e.$1] = e;
      }
      entries = byPath.values.toList();
    } else {
      entries = _walk([root], progress);
    }
    final collectMs = sw.elapsedMilliseconds;
    final out = _analyse(entries, progress);
    // ignore: avoid_print
    print('[BuddyScan] ${indexed != null ? 'MediaStore' : 'walk'}: ${entries.length} files, collect $collectMs ms, analyse ${sw.elapsedMilliseconds - collectMs} ms');
    return out;
  }

  /// Recursive listing with dart:io (used for background scans and hidden cache folders).
  static List<FileEntry> _walk(Iterable<String> starts, SendPort? progress) {
    final out = <FileEntry>[];
    final stack = [for (final s in starts) Directory(s)];
    var last = DateTime.now();
    while (stack.isNotEmpty && out.length < 300000) {
      final dir = stack.removeLast();
      List<FileSystemEntity> kids;
      try {
        kids = dir.listSync(followLinks: false);
      } catch (_) {
        continue;
      }
      for (final e in kids) {
        final name = p.basename(e.path);
        if (e is Directory) {
          final rel = e.path.length > root.length ? e.path.substring(root.length + 1) : '';
          if (_skipDirs.contains(rel)) continue;
          // Hidden folders are skipped, except caches we know are safe.
          if (name.startsWith('.') && name != '.thumbnails' && name != '.Statuses') continue;
          stack.add(e);
        } else if (e is File) {
          try {
            final st = e.statSync();
            if (st.size > 0) out.add((e.path, st.size, st.modified.millisecondsSinceEpoch));
          } catch (_) {}
          if (progress != null && DateTime.now().difference(last).inMilliseconds > 150) {
            last = DateTime.now();
            progress.send([out.length, dir.path.replaceFirst('$root/', ''), 0]);
          }
        }
      }
    }
    return out;
  }

  static Map<String, List<CleanItem>> _analyse(List<FileEntry> entries, SendPort? progress) {
    final out = {for (final k in cleanCategories.keys) k: <CleanItem>[]};
    final now = DateTime.now().millisecondsSinceEpoch;
    final bySize = <int, List<FileEntry>>{};
    var found = 0;
    void add(String cat, CleanItem item) {
      out[cat]!.add(item);
      found += item.size;
    }

    for (final (path, size, mod) in entries) {
      final rel = path.startsWith(root) ? path.substring(root.length + 1) : path;
      final lower = rel.toLowerCase();
      final ext = p.extension(path).toLowerCase();
      final ageDays = (now - mod) ~/ 86400000;
      if (lower.contains('/.thumbnails/')) {
        add('thumbs', CleanItem(path, size));
        continue;
      }
      if (lower.contains('/.statuses/')) {
        add('statuses', CleanItem(path, size));
        continue;
      }
      final inDownloads = lower.startsWith('download/');
      if (ext == '.apk' && (inDownloads || lower.contains('bluetooth'))) {
        add('apks', CleanItem(path, size));
        continue;
      }
      if (lower.contains('screenshot') && ageDays >= 60) {
        add('shots', CleanItem(path, size, '$ageDays days old'));
      } else if (inDownloads && ageDays >= 90) {
        add('oldDownloads', CleanItem(path, size, '$ageDays days old'));
      }
      if (size >= 200 * 1024 * 1024 && const {'.mp4', '.mkv', '.mov', '.avi', '.webm', '.3gp'}.contains(ext)) {
        add('bigVideos', CleanItem(path, size, '${(size / 1048576).round()} MB'));
      }
      if (size >= 50 * 1024) (bySize[size] ??= []).add((path, size, mod));
    }

    // Duplicates: only files with exactly the same size can match; confirm with a head+tail fingerprint.
    final groups = bySize.values.where((g) => g.length > 1).toList();
    var last = DateTime.now();
    for (final (gi, group) in groups.indexed) {
      if (progress != null && DateTime.now().difference(last).inMilliseconds > 150) {
        last = DateTime.now();
        progress.send([entries.length, 'Comparing possible duplicates ${gi + 1}/${groups.length}…', found]);
      }
      final byHash = <String, List<FileEntry>>{};
      for (final f in group) {
        final h = fingerprint(f.$1, f.$2);
        if (h != null) (byHash[h] ??= []).add(f);
      }
      for (final same in byHash.values) {
        if (same.length < 2) continue;
        same.sort((a, b) => a.$3.compareTo(b.$3));
        final keep = p.basename(same.first.$1);
        for (final d in same.skip(1)) {
          add('dupes', CleanItem(d.$1, d.$2, 'copy of $keep'));
        }
      }
    }
    for (final l in out.values) {
      l.sort((a, b) => b.size.compareTo(a.size));
      if (l.length > 400) l.removeRange(400, l.length);
    }
    return out;
  }

  /// MD5 of the first and last 64 KB. Files already match in exact size, so this identifies copies
  /// while reading at most 128 KB per file (whole-file hashing made scans crawl on big galleries).
  static String? fingerprint(String path, int size) {
    try {
      final raf = File(path).openSync();
      try {
        const chunk = 64 * 1024;
        if (size <= 2 * chunk) return md5.convert(raf.readSync(size)).toString();
        final head = raf.readSync(chunk);
        raf.setPositionSync(size - chunk);
        final tail = raf.readSync(chunk);
        return md5.convert([...head, ...tail]).toString();
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return null;
    }
  }

  static int total(Map<String, List<CleanItem>> r) =>
      r.values.fold(0, (a, l) => a + l.fold(0, (b, i) => b + i.size));

  static Future<void> save(Map<String, List<CleanItem>> r) async {
    await Store.setJson('clean_report', {
      'at': DateTime.now().toIso8601String(),
      'cats': r.map((k, v) => MapEntry(k, v.map((e) => e.toJson()).toList())),
    });
  }

  static (DateTime?, Map<String, List<CleanItem>>) load() {
    final j = Store.getJson('clean_report');
    if (j == null) return (null, {});
    return (
      DateTime.tryParse(j['at'] ?? ''),
      (j['cats'] as Map).map((k, v) => MapEntry(k as String, (v as List).map((e) => CleanItem.fromJson(e)).toList())),
    );
  }

  /// Deletes the given files, returns bytes freed.
  static Future<int> delete(List<CleanItem> items) async {
    var freed = 0;
    for (final i in items) {
      try {
        await File(i.path).delete();
        freed += i.size;
      } catch (_) {}
    }
    await Store.raw.setInt('freed_total', (Store.raw.getInt('freed_total') ?? 0) + freed);
    await Store.raw.setString('cleaned_on', dayKey());
    return freed;
  }
}

String fmtBytes(int b) {
  if (b >= 1 << 30) return '${(b / (1 << 30)).toStringAsFixed(2)} GB';
  if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(0)} MB';
  if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(0)} KB';
  return '$b B';
}
