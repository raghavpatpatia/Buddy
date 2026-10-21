import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/arch/load_state.dart';
import '../../../core/arch/safe_notifier.dart';
import '../../../core/native.dart';
import '../../../core/store.dart';
import '../data/cleaner.dart';

/// Where a storage scan is.
sealed class ScanStatus {
  const ScanStatus();
}

class NotScanning extends ScanStatus {
  const NotScanning();
}

class Scanning extends ScanStatus {
  final int seen, found;
  final String dir;
  const Scanning(this.seen, this.found, this.dir);
}

class ScanFailed extends ScanStatus {
  final String message;
  const ScanFailed(this.message);
}

/// Cleaner tab: scan results by category, selection, deletion and app storage insights.
class CleanController extends SafeNotifier {
  DateTime? scannedAt;
  Map<String, List<CleanItem>> categories = {};
  final selected = <String>{};
  ScanStatus scan = const NotScanning();
  LoadState<Map?> insights = const Loading();
  bool allFiles = true;

  bool get scanning => scan is Scanning;
  int get total => Cleaner.total(categories);
  int? get lastScanMs => Store.raw.getInt('clean_scan_ms');
  int get freedTotal => Store.raw.getInt('freed_total') ?? 0;
  List<CleanItem> get selectedItems => [for (final l in categories.values) ...l.where((i) => selected.contains(i.path))];

  CleanController() {
    _loadSaved();
  }

  /// Checks permissions, rescans when the last scan is over 10 minutes old, and loads app insights.
  Future<void> start() async {
    final v = await Native.permissions();
    allFiles = v['allFiles'] == true;
    notifyListeners();
    if (allFiles && (scannedAt == null || DateTime.now().difference(scannedAt!).inMinutes >= 10)) unawaited(scanNow());
    insights = Ready(await Native.appInsights());
    notifyListeners();
  }

  void _loadSaved() {
    final (at, cats) = Cleaner.load();
    scannedAt = at;
    categories = cats;
    // Pre-select only the always-safe categories (caches, installers, exact copies).
    selected
      ..clear()
      ..addAll([
        for (final e in cats.entries)
          if (cleanCategories[e.key]?.$3 == true) ...e.value.map((i) => i.path),
      ]);
  }

  Future<void> scanNow() async {
    if (scanning) return;
    scan = const Scanning(0, 0, '');
    notifyListeners();
    final started = DateTime.now();
    List<(String, int, int)>? indexed;
    try {
      indexed = await Native.mediaFiles();
    } catch (_) {}
    try {
      final r = await Cleaner.scan(indexed: indexed, onProgress: (seen, dir, found) {
        scan = Scanning(seen, found, dir);
        notifyListeners();
      });
      await Cleaner.save(r);
      await Store.raw.setInt('clean_scan_ms', DateTime.now().difference(started).inMilliseconds);
      _loadSaved();
      scan = const NotScanning();
    } catch (e, st) {
      debugPrint('[BuddyScan] failed: $e\n$st');
      scan = ScanFailed('$e');
    }
    notifyListeners();
  }

  void toggle(String path) {
    selected.contains(path) ? selected.remove(path) : selected.add(path);
    notifyListeners();
  }

  void selectAll(List<CleanItem> items, bool on) {
    on ? selected.addAll(items.map((i) => i.path)) : selected.removeAll(items.map((i) => i.path));
    notifyListeners();
  }

  /// Deletes the selected files and returns the bytes freed; the caller confirms first.
  Future<int> deleteSelected() async {
    final freed = await Cleaner.delete(selectedItems);
    for (final l in categories.values) {
      l.removeWhere((i) => selected.contains(i.path));
    }
    await Cleaner.save(categories);
    selected.clear();
    notifyListeners();
    return freed;
  }
}
