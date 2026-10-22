import 'dart:convert';
import 'dart:io';

import 'package:buddy_app/core/arch/load_state.dart';
import 'package:buddy_app/core/arch/time_sort.dart';
import 'package:buddy_app/core/store.dart';
import 'package:buddy_app/features/jobs/controller/job_profile_form.dart';
import 'package:buddy_app/features/jobs/controller/jobs_controller.dart';
import 'package:buddy_app/features/jobs/data/job_search.dart';
import 'package:buddy_app/features/jobs/data/job_sources.dart';
import 'package:buddy_app/features/jobs/data/job_store.dart';
import 'package:buddy_app/features/jobs/data/locate.dart';
import 'package:buddy_app/features/jobs/data/platforms.dart';
import 'package:buddy_app/features/jobs/model/job.dart';
import 'package:buddy_app/features/jobs/model/job_profile.dart';
import 'package:buddy_app/features/jobs/model/locations.dart';
import 'package:buddy_app/features/jobs/model/match.dart';
import 'package:buddy_app/features/jobs/model/roles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _now = DateTime(2026, 10, 22);

Job _job(String title, {String company = 'Acme', String location = 'Bengaluru, India', bool remote = false, List<String> skills = const [], int ageDays = 2, String? level}) =>
    Job(id: '$title|$company', title: title, company: company, location: location, url: 'https://x.test/$title', source: 'Test', remote: remote, skills: skills, posted: _now.subtract(Duration(days: ageDays)), level: level);

const _me = JobProfile(city: 'Bengaluru', country: 'India', skills: ['C++', 'Unity'], currentTitle: 'Game Developer', years: 1, setUp: true);

/// Source stub returning fixed jobs or throwing.
class _Src implements JobSource {
  @override
  final String name;
  final List<Job>? jobs;
  final bool game;
  int calls = 0;
  _Src(this.name, this.jobs, {this.game = false});
  @override
  bool covers(JobProfile p) => !game || p.gameFocus;
  @override
  Future<List<Job>> search(JobProfile p) async {
    calls++;
    if (jobs == null) throw Exception('down');
    return jobs!;
  }
}

late File _cache;

/// Search over [sources] caching to this test's temp file.
JobSearch _search(List<JobSource> sources) => JobSearch(sources: sources, cacheFile: () async => _cache);

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    _cache = File('${Directory.systemTemp.createTempSync('jobs').path}/cache.json');
  });

  group('levels and roles', () {
    test('reads seniority from titles', () {
      expect(levelOf('Junior Gameplay Programmer'), Level.entry);
      expect(levelOf('Software Engineer II'), Level.mid);
      expect(levelOf('Sr. Unity Developer'), Level.senior);
      expect(levelOf('Principal Engineer'), Level.lead);
      expect(levelOf('Game Programming Intern'), Level.intern);
      expect(levelOf('Gameplay Programmer'), isNull);
      expect(levelOf('Engineer', 'Entry-level'), Level.entry);
      expect(levelOf('Associate Product Manager'), Level.entry);
      expect(levelOf('Engineering Manager'), Level.lead);
    });

    test('profile defaults to SDE-1 in game development', () {
      const p = JobProfile();
      expect(p.targetRoles.single.id, 'sde1');
      expect(p.targetLevel, Level.entry);
      expect(p.gameFocus, isTrue);
      expect(p.searchPhrase, 'game developer');
      expect(p.keyword, 'game');
    });

    test('profile JSON round trip drops unknown roles and keeps a default', () {
      final p = _me.copyWith(roles: ['unity', 'sde2'], scope: JobScope.remote, focus: '');
      final back = JobProfile.fromJson(jsonDecode(jsonEncode(p.toJson())));
      expect(back.roles, ['unity', 'sde2']);
      expect(back.scope, JobScope.remote);
      expect(back.focus, '');
      expect(JobProfile.fromJson({'roles': ['bogus'], 'scope': 'mars'}).roles, ['sde1']);
      expect(JobProfile.fromJson({'scope': 'mars'}).scope, JobScope.near);
    });

    test('any-field profile still searches', () {
      const p = JobProfile(focus: '', roles: ['backend']);
      expect(p.gameFocus, isFalse);
      expect(p.searchPhrase, 'backend engineer');
      expect(p.keyword, 'engineer');
    });
  });

  group('locations', () {
    test('city aliases and nearby cities count as near', () {
      expect(inCity('IN - Bangalore, India', 'Bengaluru'), isTrue);
      expect(inCity('Gurgaon, Haryana', 'Delhi'), isTrue);
      expect(inCity('North Dakota, US', 'Kota'), isFalse);
      expect(inCity('Pune', ''), isFalse);
    });

    test('country from name or one of its cities', () {
      expect(inCountry('Pune, MH', 'India'), isTrue);
      expect(inCountry('Remote (US)', 'India'), isFalse);
      expect(inCountry('anything', ''), isFalse);
    });

    test('remote restrictions', () {
      expect(remoteOpenTo('Worldwide', 'India'), isTrue);
      expect(remoteOpenTo('', 'India'), isTrue);
      expect(remoteOpenTo('APAC', 'India'), isTrue);
      expect(remoteOpenTo('USA', 'India'), isFalse);
      expect(remoteOpenTo('US only', 'United States'), isTrue);
      expect(remoteOpenTo('Europe', ''), isFalse);
    });

    test('nearest city and timezone guess', () {
      expect(nearestCity(12.95, 77.6), 'Bengaluru');
      expect(nearestCity(0, 0), isNull);
      expect(countryFromOffset(const Duration(hours: 5, minutes: 30)), 'India');
      expect(countryFromOffset(Duration.zero), '');
    });
  });

  group('matching', () {
    test('right role near the user ranks above an off-level remote job', () {
      final lead = matchJob(_job('Lead Gameplay Engineer', remote: true, location: 'Worldwide'), _me, now: _now)!;
      final junior = matchJob(_job('Junior Game Developer', skills: ['C++', 'Unity']), _me, now: _now)!;
      expect(junior.reasons, containsAll(['Near you', 'Right level', 'Uses C++, Unity']));
      expect(junior.score, greaterThan(lead.score + 30));
    });

    test('drops jobs outside the scope, off-field roles and non-engineering titles', () {
      final jobs = [
        _job('Game Developer', location: 'Berlin, Germany'),
        _job('Game Developer', company: 'Remote US', location: 'USA', remote: true),
        _job('3D Character Artist', company: 'Riot Games'),
        _job('Developer Advocate', company: 'Unity'),
        _job('Game Developer to Teach'),
        _job('Game Producer, Gameplay'),
      ];
      expect(rankJobs(jobs, _me, now: _now), isEmpty);
      expect(rankJobs(jobs, _me.copyWith(scope: JobScope.worldwide), now: _now).map((m) => m.job.company), unorderedEquals(['Acme', 'Remote US']));
    });

    test('weak matches are left out', () {
      final weak = _job('Principal QA Engineer', location: 'San Mateo, CA', ageDays: 90);
      expect(matchJob(weak, _me.copyWith(scope: JobScope.worldwide), now: _now)!.score, lessThan(minScore));
      expect(rankJobs([weak], _me.copyWith(scope: JobScope.worldwide), now: _now), isEmpty);
    });

    test('duplicates across sources count once', () {
      final a = _job('Unity Developer', company: 'Studio X');
      final b = Job(id: 'other', title: 'Unity  developer', company: 'studio x', location: 'Bengaluru', url: 'https://y', source: 'Other');
      expect(rankJobs([a, b], _me.copyWith(roles: ['unity']), now: _now), hasLength(1));
    });

    test('marks a level up from the current job as an opportunity', () {
      final m = matchJob(_job('Game Developer II', skills: ['C++', 'Unity']), _me.copyWith(roles: ['sde1', 'gameplay']), now: _now)!;
      expect(m.opportunity, contains('step up'));
    });

    test('skill gaps come from strong matches only and need two jobs', () {
      final jobs = [
        for (var i = 0; i < 4; i++) _job('Junior Game Developer $i', skills: ['C++', 'Unreal', if (i == 0) 'Lua']),
      ];
      final gaps = skillGaps(rankJobs(jobs, _me, now: _now));
      expect(gaps.map((g) => g.$1), ['Unreal']);
      expect(gaps.first.$2, 1.0);
      expect(skillGaps(const []), isEmpty);
    });

    test('finds skills and cleans HTML', () {
      expect(findSkills('Strong C++ and C#, Unity3D, some UE5; JavaScript not Java'), containsAll(['C++', 'C#', 'Unity', 'Unreal', 'JavaScript']));
      expect(findSkills('JavaScript only'), isNot(contains('Java')));
      expect(matchJob(_job('Game Producer, Gameplay'), _me.copyWith(roles: ['gameplay', 'producer']), now: _now), isNotNull);
      expect(plainText('<p>Hi&nbsp;&amp; <b>bye</b></p>'), 'Hi & bye');
    });
  });

  group('sources', () {
    test('Hacker News post line becomes a job', () {
      final j = parseHnPost('1', 'MaFi Games | Senior SWE&#x2F;Game dev | Remote | C#<p>We build Captain of Industry in Unity.', _now)!;
      expect(j.company, 'MaFi Games');
      expect(j.title, 'Senior SWE/Game dev');
      expect(j.remote, isTrue);
      expect(j.skills, containsAll(['C#', 'Unity']));
      expect(parseHnPost('2', 'just a comment without pipes', _now), isNull);
    });

    test('Himalayas response is parsed, including pay and eligibility', () async {
      final client = MockClient((r) async {
        expect(r.url.queryParameters['country'], 'India');
        return http.Response(
            jsonEncode({
              'jobs': [
                {'title': 'Jr. Unity Developer', 'companyName': 'Co', 'locationRestrictions': ['India'], 'seniority': ['Entry-level'],
                 'minSalary': 600000, 'maxSalary': 900000, 'currency': 'INR', 'salaryPeriod': 'annual', 'pubDate': 1792203343, 'applicationLink': 'https://h/1',
                 'excerpt': '<p>Unity and C#</p>', 'categories': ['Unity-Developer']},
              ],
            }),
            200);
      });
      final jobs = await HimalayasSource(client).search(_me);
      expect(jobs.single.location, 'India');
      expect(jobs.single.salary, 'INR 600k–900k/yr');
      expect(jobs.single.level, 'Entry-level');
      expect(jobs.single.skills, containsAll(['Unity', 'C#']));
    });

    test('a source with a bad response throws (and is reported as failed)', () async {
      final client = MockClient((_) async => http.Response('nope', 503));
      await expectLater(RemotiveSource(client).search(_me), throwsException);
    });

    test('studio boards skip a studio that is down and only run for game searches', () async {
      final client = MockClient((r) async {
        if (r.url.host == 'boards-api.greenhouse.io' && r.url.path.contains('epicgames')) {
          return http.Response(jsonEncode({'jobs': [{'id': 1, 'title': 'Gameplay Programmer', 'location': {'name': 'Cary, NC'}, 'absolute_url': 'https://e/1'}]}), 200);
        }
        return http.Response('down', 500);
      });
      final s = StudioBoardsSource(client);
      expect(s.covers(_me.copyWith(focus: 'Fintech')), isFalse);
      final jobs = await s.search(_me);
      expect(jobs.single.company, 'Epic Games');
    });
  });

  group('search service', () {
    test('keeps working when some sources fail, and caches for an hour', () async {
      final ok = _Src('A', [_job('Game Developer')]);
      final search = _search([ok, _Src('B', null), _Src('Studios', [_job('Unity Dev')], game: true)]);
      final r = await search.search(_me);
      expect(r.jobs, hasLength(2));
      expect(r.failed, ['B']);
      await search.search(_me);
      expect(ok.calls, 1);
      await search.search(_me, force: true);
      expect(ok.calls, 2);
    });

    test('everything down: cached results, else an error', () async {
      final down = _search([_Src('A', null)]);
      await expectLater(down.search(_me), throwsException);
      await _search([_Src('A', [_job('Game Developer')])]).search(_me);
      final r = await down.search(_me, force: true);
      expect(r.jobs.single.title, 'Game Developer');
    });

    test('cache lives in its own file and the old prefs copy is removed', () async {
      await Store.raw.setString('jobs_cache', 'old');
      await _search([_Src('A', [_job('Game Developer')])]).search(_me);
      expect(_cache.readAsStringSync(), contains('Game Developer'));
      expect(Store.raw.containsKey('jobs_cache'), isFalse);
      _cache.writeAsStringSync('{not json');
      expect((await _search([_Src('A', [_job('Unity Dev')])]).search(_me)).jobs.single.title, 'Unity Dev');
    });

    test('drops postings without a title or a web link', () async {
      final bad = Job(id: 'x', title: '', company: 'c', location: '', url: 'https://x', source: 's');
      final noLink = Job(id: 'y', title: 'Dev', company: 'c', location: '', url: 'mailto:a@b', source: 's');
      final r = await _search([_Src('A', [bad, noLink, _job('Game Developer')])]).search(_me);
      expect(r.jobs.single.title, 'Game Developer');
    });
  });

  group('platform links', () {
    test('India gets Naukri, encoded queries and the local Indeed', () {
      final links = {for (final p in platformLinks(_me)) p.name: p.url};
      expect(links['Naukri'], 'https://www.naukri.com/game-developer-jobs-in-bengaluru');
      expect(links['Indeed'], startsWith('https://in.indeed.com/jobs?q=game+developer&l=Bengaluru'));
      expect(links['LinkedIn'], contains('f_E=2'));
      expect(links['Wellfound'], 'https://wellfound.com/role/l/game-developer/bangalore');
      expect(links.keys, contains('Hitmarker'));
    });

    test('other countries and remote searches', () {
      final p = _me.copyWith(country: 'Germany', city: 'Berlin', scope: JobScope.remote, focus: 'Fintech', roles: ['backend']);
      final links = {for (final l in platformLinks(p)) l.name: l.url};
      expect(links.containsKey('Naukri'), isFalse);
      expect(links.containsKey('Hitmarker'), isFalse);
      expect(links['Indeed'], 'https://www.indeed.com/jobs?q=backend+engineer&l=Remote');
      expect(links['LinkedIn'], contains('f_WT=2'));
      for (final u in links.values) {
        expect(Uri.parse(u).isAbsolute, isTrue);
      }
    });
  });

  group('profile form', () {
    test('skills: comma lists, trims, no duplicates, capped', () {
      final f = JobProfileForm(const JobProfile(), locate: () async => ('', ''));
      f.addSkills(' C++ , c++, Unity,, ');
      expect(f.skills, ['C++', 'Unity']);
      f.addSkills(List.generate(40, (i) => 'S$i').join(','));
      expect(f.skills, hasLength(JobProfileForm.maxSkills));
      f.addSkills('x' * 41);
      expect(f.skills.where((s) => s.startsWith('x')), isEmpty);
    });

    test('always keeps at least one role and clamps years', () {
      final f = JobProfileForm(const JobProfile(), locate: () async => ('', ''));
      f.toggleRole('sde1');
      expect(f.roles, ['sde1']);
      f.toggleRole('unity');
      f.toggleRole('sde1');
      expect(f.roles, ['unity']);
      f.setYears(-3);
      expect(f.years, 0);
      f.setYears(99);
      expect(f.years, 40);
    });

    test('game suggestions come first and skip added skills', () {
      final f = JobProfileForm(const JobProfile(skills: ['C++']), locate: () async => ('', ''));
      expect(f.suggestions('Game development').take(3), ['C#', 'Unity', 'Unreal']);
    });

    test('detect returns null when nothing is known', () async {
      final f = JobProfileForm(const JobProfile(), locate: () async => ('', ''));
      expect(await f.detect(), isNull);
      expect(f.locating, isFalse);
    });
  });

  group('controller', () {
    JobsController make(List<Job>? jobs, {Future<String?> Function(String, String, {int maxTokens})? ask}) => JobsController(
          search: _search([_Src('A', jobs)]),
          store: JobStore.instance,
          ask: ask ?? (s, p, {int maxTokens = 0}) async => null,
          locate: () async => ('Pune', 'India'),
        );

    test('fills the place near the user but waits for setup before searching', () async {
      final c = make([_job('Game Developer')]);
      await c.init();
      expect(c.profile.city, 'Pune');
      expect(c.state, isA<Idle>());
      c.dispose();
    });

    test('saving the profile searches, ranks and keeps role filter valid', () async {
      final c = make([_job('Junior Game Developer', location: 'Pune'), _job('Unity Developer', location: 'Pune')]);
      await c.init();
      c.setRoleFilter('unity');
      await c.saveProfile(_me.copyWith(city: 'Pune', roles: ['sde1']));
      expect(c.profile.setUp, isTrue);
      expect(c.roleFilter, isNull);
      expect(c.matches, hasLength(2));
      expect(identical(c.matches, c.matches), isTrue);
      c.dispose();
    });

    test('save and unsave jobs survive a new controller', () async {
      final c = make(const []);
      final j = _job('Game Developer');
      await c.toggleSave(j);
      expect(make(const []).saved.single.id, j.id);
      await c.toggleSave(j);
      expect(c.saved, isEmpty);
      c.dispose();
    });

    test('advice: AI plan, or a quick offline plan when the cloud brain is off', () async {
      final off = make([_job('Game Developer')]);
      await off.saveProfile(_me);
      await off.askAdvice();
      expect(off.adviceOffline, isTrue);
      expect((off.advice as Ready<String>).value, contains('Apply first to: Game Developer at Acme'));
      String? sent;
      final on = make([_job('Game Developer')], ask: (s, p, {int maxTokens = 0}) async {
        sent = p;
        return '• Apply to Acme';
      });
      await on.saveProfile(_me);
      await on.askAdvice();
      expect((on.advice as Ready<String>).value, '• Apply to Acme');
      expect(sent, contains('Game Developer at Acme'));
      off.dispose();
      on.dispose();
    });

    test('sort by date: newest, oldest, back to best match; saved jobs follow; remembered', () async {
      final c = make([_job('Junior Game Developer', ageDays: 9, skills: ['C++', 'Unity']), _job('Game Developer', ageDays: 1), _job('Unity Developer', ageDays: 5)]);
      await c.saveProfile(_me.copyWith(roles: ['sde1', 'unity']));
      final best = c.visible.map((m) => m.job.title).toList();
      expect(best.first, 'Junior Game Developer');
      c.setSort(TimeSort.newest);
      expect(c.visible.map((m) => m.job.title), ['Game Developer', 'Unity Developer', 'Junior Game Developer']);
      c.setSort(TimeSort.oldest);
      expect(c.visible.first.job.title, 'Junior Game Developer');
      for (final m in c.visible) {
        await c.toggleSave(m.job);
      }
      expect(c.saved.first.title, 'Junior Game Developer');
      expect(make(const []).sort, TimeSort.oldest);
      c.setSort(TimeSort.best);
      expect(c.visible.map((m) => m.job.title).toList(), best);
      expect(c.saved.first.title, 'Game Developer');
      c.dispose();
    });

    test('long lists page by 30 and reset on a new search', () async {
      final c = make([for (var i = 0; i < 70; i++) _job('Game Developer $i')]);
      await c.saveProfile(_me);
      expect(c.visible.length, 70);
      expect(c.shown, 30);
      c.showMore();
      expect(c.shown, 60);
      await c.search(force: true);
      expect(c.shown, 30);
      c.dispose();
    });

    test('start over clears profile, saved jobs and results but keeps the place', () async {
      final c = make([_job('Game Developer')]);
      await c.saveProfile(_me);
      await c.toggleSave(_job('Game Developer'));
      await c.reset();
      expect(c.profile.setUp, isFalse);
      expect(c.profile.currentTitle, '');
      expect(c.profile.city, 'Bengaluru');
      expect(c.saved, isEmpty);
      expect(c.state, isA<Idle>());
      expect(JobStore.instance.profile.setUp, isFalse);
      c.dispose();
    });

    test('no sources reachable shows a failure', () async {
      final c = make(null);
      await c.saveProfile(_me);
      expect(c.state, isA<Failed>());
      c.dispose();
    });
  });
}
