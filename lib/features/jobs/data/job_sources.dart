import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/job.dart';
import '../model/job_profile.dart';
import '../model/locations.dart';

/// One place jobs come from (Strategy); each source only needs the user's profile.
abstract interface class JobSource {
  String get name;

  /// False when this source has nothing for the profile (e.g. game studios for a non-game search).
  bool covers(JobProfile p);
  Future<List<Job>> search(JobProfile p);
}

const _ua = {'User-Agent': 'BuddyApp/1.0 (personal Android app)', 'Accept': 'application/json'};

/// GET that returns decoded JSON or throws; [client] is swappable for tests.
Future<dynamic> getJson(http.Client client, String url) async {
  final r = await client.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 15));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
}

String _q(String s) => Uri.encodeQueryComponent(s);

String _short(String text) => text.length <= 400 ? text : '${text.substring(0, 400).trimRight()}…';

String? _pay(num? min, num? max, String? currency, [String? period]) {
  if ((min ?? 0) <= 0 && (max ?? 0) <= 0) return null;
  String k(num v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';
  final c = currency ?? '';
  final range = (min ?? 0) > 0 && (max ?? 0) > 0 ? '${k(min!)}–${k(max!)}' : k((min ?? 0) > 0 ? min! : max!);
  final per = switch (period?.toLowerCase()) { 'hourly' || 'hour' => '/hr', 'monthly' || 'month' => '/mo', 'annual' || 'yearly' || 'year' => '/yr', _ => '' };
  return '$c $range$per'.trim();
}

DateTime? _date(dynamic v) => switch (v) {
      final num n => DateTime.fromMillisecondsSinceEpoch((n < 1e12 ? n * 1000 : n).toInt()),
      final String s => DateTime.tryParse(s)?.toLocal(),
      _ => null,
    };

/// Remotive: remote jobs worldwide.
class RemotiveSource implements JobSource {
  final http.Client _client;
  RemotiveSource(this._client);
  @override
  String get name => 'Remotive';
  @override
  bool covers(JobProfile p) => true;

  @override
  Future<List<Job>> search(JobProfile p) async {
    final d = await getJson(_client, 'https://remotive.com/api/remote-jobs?search=${_q(p.keyword)}&limit=60');
    return [
      for (final j in (d['jobs'] as List).cast<Map>())
        () {
          final text = plainText(j['description'] ?? '');
          return Job(
            id: 'remotive:${j['id']}',
            title: j['title'] ?? '',
            company: j['company_name'] ?? '',
            location: j['candidate_required_location'] ?? '',
            url: j['url'] ?? '',
            source: name,
            summary: _short(text),
            remote: true,
            posted: _date(j['publication_date']),
            salary: (j['salary'] as String?)?.trim().isEmpty ?? true ? null : j['salary'],
            skills: findSkills('$text ${(j['tags'] as List? ?? const []).join(' ')}'),
          );
        }(),
    ];
  }
}

/// Himalayas: remote jobs with country eligibility, seniority and pay.
class HimalayasSource implements JobSource {
  final http.Client _client;
  HimalayasSource(this._client);
  @override
  String get name => 'Himalayas';
  @override
  bool covers(JobProfile p) => true;

  @override
  Future<List<Job>> search(JobProfile p) async {
    final country = p.scope == JobScope.worldwide || p.country.isEmpty ? '' : '&country=${_q(p.country)}';
    final d = await getJson(_client, 'https://himalayas.app/jobs/api/search?q=${_q(p.searchPhrase)}$country');
    return [
      for (final j in (d['jobs'] as List).cast<Map>())
        () {
          final text = plainText(j['description'] ?? j['excerpt'] ?? '');
          final where = (j['locationRestrictions'] as List? ?? const []).join(', ');
          return Job(
            id: 'himalayas:${j['guid'] ?? j['applicationLink']}',
            title: j['title'] ?? '',
            company: j['companyName'] ?? '',
            location: where.isEmpty ? 'Worldwide' : where,
            url: j['applicationLink'] ?? j['guid'] ?? '',
            source: name,
            summary: _short(plainText(j['excerpt'] ?? '')),
            remote: true,
            posted: _date(j['pubDate']),
            salary: _pay(j['minSalary'], j['maxSalary'], j['currency'], j['salaryPeriod']),
            level: (j['seniority'] as List?)?.join(' '),
            skills: findSkills('$text ${(j['categories'] as List? ?? const []).join(' ').replaceAll('-', ' ')}'),
          );
        }(),
    ];
  }
}

/// Jobicy: remote jobs with region and level.
class JobicySource implements JobSource {
  final http.Client _client;
  JobicySource(this._client);
  @override
  String get name => 'Jobicy';
  @override
  bool covers(JobProfile p) => true;

  @override
  Future<List<Job>> search(JobProfile p) async {
    final d = await getJson(_client, 'https://jobicy.com/api/v2/remote-jobs?count=50&tag=${_q(p.keyword)}');
    return [
      for (final j in (d['jobs'] as List? ?? const []).cast<Map>())
        () {
          final text = plainText(j['jobDescription'] ?? '');
          return Job(
            id: 'jobicy:${j['id']}',
            title: plainText(j['jobTitle'] ?? ''),
            company: j['companyName'] ?? '',
            location: j['jobGeo'] ?? '',
            url: j['url'] ?? '',
            source: name,
            summary: _short(plainText(j['jobExcerpt'] ?? '')),
            remote: true,
            posted: _date(j['pubDate']),
            salary: _pay(j['annualSalaryMin'] as num?, j['annualSalaryMax'] as num?, j['salaryCurrency']),
            level: j['jobLevel'],
            skills: findSkills(text),
          );
        }(),
    ];
  }
}

/// Remote OK: remote tech jobs; postings link back to remoteok.com as its terms ask.
class RemoteOkSource implements JobSource {
  final http.Client _client;
  RemoteOkSource(this._client);
  @override
  String get name => 'Remote OK';
  @override
  bool covers(JobProfile p) => true;

  @override
  Future<List<Job>> search(JobProfile p) async {
    final d = await getJson(_client, 'https://remoteok.com/api?tag=${_q(p.keyword)}') as List;
    return [
      for (final j in d.skip(1).cast<Map>())
        if (j['position'] != null)
          () {
            final text = plainText(j['description'] ?? '');
            return Job(
              id: 'remoteok:${j['id']}',
              title: j['position'],
              company: j['company'] ?? '',
              location: j['location'] ?? '',
              url: j['url'] ?? '',
              source: name,
              summary: _short(text),
              remote: true,
              posted: _date(j['date']),
              salary: _pay(j['salary_min'] as num?, j['salary_max'] as num?, 'USD', 'annual'),
              skills: findSkills('$text ${(j['tags'] as List? ?? const []).join(' ')}'),
            );
          }(),
    ];
  }
}

/// Hacker News "Who is hiring?": this month's posts, onsite and remote, worldwide.
class HackerNewsSource implements JobSource {
  final http.Client _client;
  HackerNewsSource(this._client);
  @override
  String get name => 'Hacker News';
  @override
  bool covers(JobProfile p) => true;

  @override
  Future<List<Job>> search(JobProfile p) async {
    final stories = await getJson(_client, 'https://hn.algolia.com/api/v1/search_by_date?tags=story,author_whoishiring&hitsPerPage=5');
    final story = (stories['hits'] as List).cast<Map>().where((h) => '${h['title']}'.contains('Who is hiring')).firstOrNull;
    if (story == null) return const [];
    final id = '${story['objectID']}';
    final d = await getJson(_client, 'https://hn.algolia.com/api/v1/search?tags=comment,story_$id&query=${_q(p.keyword)}&hitsPerPage=100');
    final out = <Job>[];
    for (final c in (d['hits'] as List).cast<Map>()) {
      if ('${c['parent_id']}' != id) continue;
      final job = parseHnPost('${c['objectID']}', c['comment_text'] ?? '', _date(c['created_at']));
      if (job != null) out.add(job);
    }
    return out;
  }
}

/// Reads "Company | Role | Location | …" from the first line of a hiring post.
Job? parseHnPost(String id, String html, DateTime? posted) {
  final firstLine = plainText(html.split(RegExp(r'<p>|\n')).first);
  final parts = firstLine.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.length < 2) return null;
  final isPlace = RegExp(r'remote|onsite|on-site|hybrid|,', caseSensitive: false);
  final isRole = RegExp(r'engineer|developer|programmer|designer|artist|manager|scientist|lead|sre|devops|intern', caseSensitive: false);
  final role = parts.skip(1).where(isRole.hasMatch).firstOrNull ?? parts[1];
  final place = parts.skip(1).where((s) => s != role && isPlace.hasMatch(s)).join(' · ');
  final text = plainText(html);
  return Job(
    id: 'hn:$id',
    title: role.length > 90 ? '${role.substring(0, 90)}…' : role,
    company: parts.first,
    location: place,
    url: 'https://news.ycombinator.com/item?id=$id',
    source: 'Hacker News',
    summary: _short(text.substring(firstLine.length.clamp(0, text.length)).trim()),
    remote: RegExp('remote', caseSensitive: false).hasMatch(place),
    posted: posted,
    skills: findSkills(text),
  );
}

/// Careers boards of well-known game studios (Greenhouse, Ashby, SmartRecruiters); game searches only.
class StudioBoardsSource implements JobSource {
  final http.Client _client;
  StudioBoardsSource(this._client);
  @override
  String get name => 'Game studios';
  @override
  bool covers(JobProfile p) => p.gameFocus;

  static const greenhouse = {
    'riotgames': 'Riot Games', 'epicgames': 'Epic Games', '2k': '2K', 'roblox': 'Roblox', 'rockstargames': 'Rockstar Games',
    'scopely': 'Scopely', 'insomniac': 'Insomniac Games', 'naughtydog': 'Naughty Dog', 'krafton': 'KRAFTON', 'bungie': 'Bungie',
  };
  static const ashby = {'supercell': 'Supercell', 'voodoo': 'Voodoo'};
  static const smartRecruiters = {'Ubisoft2': 'Ubisoft', 'Gameloft': 'Gameloft'};

  @override
  Future<List<Job>> search(JobProfile p) async {
    final code = p.scope == JobScope.near || p.scope == JobScope.country ? countryCode(p.country) : null;
    final boards = <Future<List<Job>>>[
      for (final e in greenhouse.entries) _greenhouse(e.key, e.value),
      for (final e in ashby.entries) _ashby(e.key, e.value),
      for (final e in smartRecruiters.entries) _smart(e.key, e.value, code),
    ];
    // One studio being down shouldn't hide the others.
    final lists = await Future.wait(boards.map((f) => f.catchError((_) => <Job>[])));
    return lists.expand((l) => l).toList();
  }

  Future<List<Job>> _greenhouse(String board, String company) async {
    final d = await getJson(_client, 'https://boards-api.greenhouse.io/v1/boards/$board/jobs');
    return [
      for (final j in (d['jobs'] as List).cast<Map>())
        Job(
          id: 'gh:$board:${j['id']}',
          title: '${j['title']}'.trim(),
          company: company,
          location: j['location']?['name'] ?? '',
          url: j['absolute_url'] ?? '',
          source: company,
          remote: RegExp('remote', caseSensitive: false).hasMatch(j['location']?['name'] ?? ''),
          posted: _date(j['first_published'] ?? j['updated_at']),
          skills: findSkills('${j['title']}'),
        ),
    ];
  }

  Future<List<Job>> _ashby(String board, String company) async {
    final d = await getJson(_client, 'https://api.ashbyhq.com/posting-api/job-board/$board');
    return [
      for (final j in (d['jobs'] as List).cast<Map>())
        if (j['isListed'] != false)
          Job(
            id: 'ashby:$board:${j['id']}',
            title: j['title'] ?? '',
            company: company,
            location: [j['location'], j['address']?['postalAddress']?['addressCountry'], for (final s in (j['secondaryLocations'] as List? ?? const [])) s['location']]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(', '),
            url: j['jobUrl'] ?? '',
            source: company,
            summary: _short(j['descriptionPlain'] ?? ''),
            remote: j['isRemote'] == true,
            posted: _date(j['publishedAt']),
            skills: findSkills('${j['title']} ${j['descriptionPlain'] ?? ''}'),
          ),
    ];
  }

  Future<List<Job>> _smart(String id, String company, String? country) async {
    final filter = country == null ? '' : '&country=$country';
    final d = await getJson(_client, 'https://api.smartrecruiters.com/v1/companies/$id/postings?limit=100$filter');
    return [
      for (final j in (d['content'] as List).cast<Map>())
        Job(
          id: 'sr:$id:${j['id']}',
          title: j['name'] ?? '',
          company: company,
          location: j['location']?['fullLocation'] ?? '',
          url: 'https://jobs.smartrecruiters.com/$id/${j['id']}',
          source: company,
          remote: j['location']?['remote'] == true,
          posted: _date(j['releasedDate']),
          level: j['experienceLevel']?['label'],
          skills: findSkills('${j['name']}'),
        ),
    ];
  }
}
