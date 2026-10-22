import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/store.dart';
import '../model/job.dart';
import '../model/job_profile.dart';
import 'job_sources.dart';

/// Jobs from every source plus the names of sources that couldn't be reached.
typedef JobResults = ({List<Job> jobs, List<String> failed, DateTime at});

/// Asks every covering source at once; cached for an hour per search (in its own file, it can be ~0.5 MB) and used offline.
class JobSearch {
  JobSearch({List<JobSource>? sources, http.Client? client, Future<File> Function()? cacheFile})
      : sources = sources ?? defaultSources(client ?? http.Client()),
        _cacheFile = cacheFile ?? _defaultCacheFile;

  final List<JobSource> sources;
  final Future<File> Function() _cacheFile;
  static const _ttl = Duration(hours: 1);

  static Future<File> _defaultCacheFile() async => File('${(await getApplicationSupportDirectory()).path}/jobs_cache.json');

  static List<JobSource> defaultSources(http.Client c) =>
      [HimalayasSource(c), RemotiveSource(c), JobicySource(c), RemoteOkSource(c), HackerNewsSource(c), StudioBoardsSource(c)];

  static String cacheKey(JobProfile p) => [p.keyword, p.searchPhrase, p.scope.name, p.country, p.gameFocus].join('|');

  Future<JobResults> search(JobProfile p, {bool force = false}) async {
    final hit = await _read(cacheKey(p));
    if (!force && hit != null && DateTime.now().difference(hit.at) < _ttl) return hit;

    final active = sources.where((s) => s.covers(p)).toList();
    final failed = <String>[];
    final lists = await Future.wait(active.map((s) => s.search(p).catchError((Object _) {
          failed.add(s.name);
          return <Job>[];
        })));
    if (failed.length == active.length) {
      if (hit != null) return hit;
      throw Exception('No job source reachable');
    }
    final res = (jobs: lists.expand((l) => l).where((j) => j.title.isNotEmpty && j.url.startsWith('http')).toList(), failed: failed, at: DateTime.now());
    await _write(cacheKey(p), res);
    return res;
  }

  /// Cached results for [key], or null when missing, for another search, or unreadable.
  Future<JobResults?> _read(String key) async {
    try {
      final m = jsonDecode(await (await _cacheFile()).readAsString()) as Map;
      if (m['key'] != key) return null;
      return (
        jobs: [for (final j in m['jobs'] as List) Job.fromJson(j)],
        failed: [for (final f in m['failed'] as List) '$f'],
        at: DateTime.parse(m['at']),
      );
    } catch (_) {
      return null;
    }
  }

  /// Best effort: a failed write only costs a re-download next time.
  Future<void> _write(String key, JobResults r) async {
    try {
      final body = {'key': key, 'at': r.at.toIso8601String(), 'failed': r.failed, 'jobs': [for (final j in r.jobs) j.toJson()]};
      await (await _cacheFile()).writeAsString(jsonEncode(body));
      // Older builds kept this cache in prefs, where it slowed every settings write.
      if (Store.raw.containsKey('jobs_cache')) await Store.raw.remove('jobs_cache');
    } catch (_) {}
  }
}
