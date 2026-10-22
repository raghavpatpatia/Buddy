import '../../../core/arch/load_state.dart';
import '../../../core/arch/time_sort.dart';
import '../../../core/store.dart';
import '../../money/data/ai.dart';
import '../data/job_search.dart';
import '../data/job_store.dart';
import '../data/locate.dart';
import '../data/platforms.dart';
import '../model/job.dart';
import '../model/job_profile.dart';
import '../model/match.dart';
import '../model/roles.dart';

/// Where the user's city and country come from; swappable for tests.
typedef Locate = Future<(String, String)> Function();

/// Jobs tab: the profile, search across sources, ranking, saved jobs and AI career advice.
class JobsController extends AsyncController<JobResults> {
  JobsController({JobSearch? search, JobStore? store, this._ask = askBuddy, this._locate = nearUser})
      : _search = search ?? JobSearch(),
        _store = store ?? JobStore.instance {
    profile = _store.profile;
    _store.saved.addListener(notifyListeners);
  }

  final JobSearch _search;
  final JobStore _store;
  final AiAsk _ask;
  final Locate _locate;

  late JobProfile profile;
  String? roleFilter;
  bool showSaved = false;
  LoadState<String> advice = const Idle();

  /// Order of the matches and saved jobs; remembered.
  TimeSort sort = TimeSort.values.asNameMap()[Store.raw.getString('jobs_sort')] ?? TimeSort.best;

  static const sortLabels = {TimeSort.best: 'Best match', TimeSort.newest: 'Newest', TimeSort.oldest: 'Oldest'};

  /// True when [advice] came from [quickPlan] because the cloud brain was unavailable.
  bool adviceOffline = false;

  /// How many matches the list shows; grows with "Show more".
  int shown = pageSize;
  static const pageSize = 30;

  /// Fills in the place near the user when the profile has none, then searches if set up.
  Future<void> init() async {
    if (profile.city.isEmpty && profile.country.isEmpty) {
      final (city, country) = await _locate();
      profile = profile.copyWith(city: city, country: country);
      notifyListeners();
    }
    if (profile.setUp) await search();
  }

  Future<void> search({bool force = false}) {
    shown = pageSize;
    return run(() => _search.search(profile, force: force), errorText: 'Couldn\'t reach any job site. Check your internet and pull to refresh.');
  }

  JobResults? _rankedFrom;
  JobProfile? _rankedFor;
  List<JobMatch> _ranked = const [];

  /// Every matching job, best first; recomputed only when results or profile change.
  List<JobMatch> get matches {
    final r = state.data;
    if (r == null) return const [];
    if (!identical(r, _rankedFrom) || !identical(profile, _rankedFor)) {
      _ranked = rankJobs(r.jobs, profile);
      _rankedFrom = r;
      _rankedFor = profile;
    }
    return _ranked;
  }

  /// Matches narrowed to the chosen role chip, in the chosen order.
  List<JobMatch> get visible {
    final role = roleFilter == null ? null : roleById(roleFilter!);
    final list = role == null ? matches : matches.where((m) => role.keywords.any((k) => m.job.title.toLowerCase().contains(k))).toList();
    return sortByTime(list, (m) => m.job.posted, sort);
  }

  List<JobMatch> get opportunities => matches.where((m) => m.opportunity != null).take(3).toList();
  List<(String, double)> get gaps => skillGaps(matches);
  List<Platform> get platforms => platformLinks(profile);
  List<String> get failedSources => state.data?.failed ?? const [];

  /// Saved jobs: newest first unless the user picked oldest.
  List<Job> get saved => sortByTime(_store.saved.all.toList(), (j) => j.posted, sort == TimeSort.oldest ? TimeSort.oldest : TimeSort.newest);
  bool isSaved(Job j) => _store.saved.contains(j.id);
  Future<void> toggleSave(Job j) => isSaved(j) ? _store.saved.remove(j.id) : _store.saved.put(j);

  void setSort(TimeSort s) {
    Store.raw.setString('jobs_sort', s.name);
    sort = s;
    shown = pageSize;
    notifyListeners();
  }

  void showMore() {
    shown += pageSize;
    notifyListeners();
  }

  void setRoleFilter(String? id) {
    roleFilter = id;
    shown = pageSize;
    notifyListeners();
  }

  void setShowSaved(bool v) {
    showSaved = v;
    notifyListeners();
  }

  Future<void> setScope(JobScope s) async {
    if (s == profile.scope) return;
    profile = profile.copyWith(scope: s);
    advice = const Idle();
    await _store.saveProfile(profile);
    await search();
  }

  Future<void> saveProfile(JobProfile p) async {
    profile = p.copyWith(setUp: true);
    if (roleFilter != null && !profile.roles.contains(roleFilter)) roleFilter = null;
    advice = const Idle();
    await _store.saveProfile(profile);
    await search();
  }

  /// Back to the first-run state: default profile near the same place, no saved jobs, no results.
  Future<void> reset() async {
    for (final j in saved) {
      await _store.saved.remove(j.id);
    }
    profile = JobProfile(city: profile.city, country: profile.country);
    roleFilter = null;
    showSaved = false;
    advice = const Idle();
    await _store.saveProfile(profile);
    state = const Idle();
  }

  /// A short career plan from the cloud brain; it sees the profile and job titles only.
  Future<void> askAdvice() async {
    advice = const Loading();
    notifyListeners();
    final p = profile;
    final top = matches.take(8).map((m) => '- ${m.job.title} at ${m.job.company} (${m.job.location})').join('\n');
    final gapText = gaps.map((g) => '${g.$1} (${(g.$2 * 100).round()}% of jobs)').join(', ');
    final prompt = '''Current job: ${p.currentTitle.isEmpty ? 'not given' : p.currentTitle}, ${p.years} years experience.
Skills: ${p.skills.isEmpty ? 'not given' : p.skills.join(', ')}.
Looking for: ${p.targetRoles.map((r) => r.label).join(', ')} in ${p.focus}, ${p.scopeLabel(p.scope)}.
Skills employers ask for that they lack: ${gapText.isEmpty ? 'none found' : gapText}.
Best matching openings now:
$top''';
    final r = await _ask(
      'You are a practical career coach. Give a short plan in 5 bullet points: which openings to apply to first and why, '
      'one skill to learn this month, how to stand out, and one better opportunity to aim for in a year. Plain text, no markdown headers.',
      prompt,
      maxTokens: 500,
    );
    adviceOffline = r == null || r.isEmpty;
    advice = Ready(adviceOffline ? quickPlan(p, matches, gaps) : r!);
    notifyListeners();
  }

  @override
  void dispose() {
    _store.saved.removeListener(notifyListeners);
    super.dispose();
  }
}
