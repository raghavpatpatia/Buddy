import 'job.dart';
import 'job_profile.dart';
import 'locations.dart';
import 'roles.dart';

/// A job scored against the user's profile.
class JobMatch {
  final Job job;
  final int score;
  final List<String> reasons;

  /// Skills the posting asks for that the user hasn't listed.
  final List<String> missing;

  /// Why this is a step up for the user, or null when it isn't one.
  final String? opportunity;

  const JobMatch(this.job, this.score, this.reasons, this.missing, this.opportunity);
}

/// True when the job's place fits the chosen search scope.
bool fitsScope(Job j, JobProfile p) => switch (p.scope) {
      JobScope.near => inCity(j.location, p.city) || (p.city.isEmpty && inCountry(j.location, p.country)) || (j.remote && remoteOpenTo(j.location, p.country)),
      JobScope.country => inCountry(j.location, p.country) || (j.remote && remoteOpenTo(j.location, p.country)),
      JobScope.remote => j.remote && remoteOpenTo(j.location, p.country),
      JobScope.worldwide => true,
    };

/// Titles with these words aren't building software, even if they say "engineer" or "developer".
final _notEngineering = RegExp(r'\b(sales|support|evangelist|advocate|recruit\w*|customer|account|marketing|teach\w*|tutor|clases|instructor|trainer|community|engagement|relations|curriculum)\b', caseSensitive: false);

/// Non-programming crafts (title word → role id) that only show when the user picked that role.
const _otherCrafts = {'producer': 'producer', 'artist': 'techart', 'designer': 'designer', 'product manager': 'pm', 'animator': 'techart', 'animation': 'techart'};

final _termRes = <String, RegExp>{};

bool _has(String text, String term) => _termRes.putIfAbsent(term, () => RegExp('(^|[^a-z0-9])${RegExp.escape(term)}([^a-z0-9]|\$)')).hasMatch(text);

/// Scores [j] for [p] from 0 to 100; null when the job is off-target (wrong field or out of scope).
JobMatch? matchJob(Job j, JobProfile p, {DateTime? now}) {
  if (!fitsScope(j, p)) return null;
  final title = j.title.toLowerCase();
  final body = '${j.company} ${j.summary} ${j.skills.join(' ')}'.toLowerCase();
  final reasons = <String>[];
  var score = 0;

  if (_notEngineering.hasMatch(title)) return null;
  for (final MapEntry(key: word, value: role) in _otherCrafts.entries) {
    if (_has(title, word) && !p.roles.contains(role)) return null;
  }
  final specific = p.targetRoles.where((r) => !r.generic && r.keywords.any((k) => _has(title, k))).firstOrNull;
  final generic = p.targetRoles.any((r) => r.generic && r.keywords.any((k) => _has(title, k)));
  if (specific != null) {
    score += 35;
    reasons.add('${specific.label} role');
  } else if (generic) {
    score += 25;
    reasons.add('Engineering role');
  }

  final focusInTitle = p.focusTerms.any((t) => _has(title, t));
  final focusInBody = !focusInTitle && p.focusTerms.any((t) => _has(body, t));
  final studio = p.gameFocus && _studios.any((s) => j.company.toLowerCase().contains(s));
  if (focusInTitle) {
    score += 20;
    reasons.add(p.gameFocus ? 'Game dev' : 'Matches ${p.focus}');
  } else if (studio) {
    score += 15;
    reasons.add('Game studio');
  } else if (focusInBody) {
    score += 10;
  }
  if (specific == null && !generic) return null;

  final mine = {for (final s in p.skills) s.toLowerCase()};
  final wanted = {...j.skills, ...findSkills(j.title)};
  final have = [for (final s in wanted) if (mine.contains(s.toLowerCase())) s];
  final missing = [for (final s in wanted) if (!mine.contains(s.toLowerCase())) s];
  score += (have.length * 8).clamp(0, 24);
  if (have.isNotEmpty) reasons.add('Uses ${have.take(3).join(', ')}');

  final lv = levelOf(j.title, j.level);
  final gap = lv == null ? null : lv.index - p.targetLevel.index;
  switch (gap) {
    case null:
      score += 6;
    case 0:
      score += 15;
      reasons.add('Right level');
    case 1:
      score += 4;
    case -1:
      score += 6;
    default:
      score -= gap > 0 ? 25 : 10;
  }

  if (inCity(j.location, p.city)) {
    score += p.scope == JobScope.near ? 20 : 12;
    reasons.add('Near you');
  } else if (j.remote) {
    score += 8;
    reasons.add('Remote');
  } else if (inCountry(j.location, p.country)) {
    score += 6;
  }

  final age = j.posted == null ? null : (now ?? DateTime.now()).difference(j.posted!).inDays;
  if (age != null && age <= 7) {
    score += 5;
    reasons.add('New');
  } else if (age != null && age > 60) {
    score -= 5;
  }

  final opp = _opportunity(j, p, lv, score);
  return JobMatch(j, score.clamp(0, 100), reasons, missing, opp);
}

/// Why a strong match is better than what the user has now; null when it isn't.
String? _opportunity(Job j, JobProfile p, Level? lv, int score) {
  if (score < 55) return null;
  if (p.currentTitle.isNotEmpty && lv != null && lv.index == p.currentLevel.index + 1) return 'A step up to ${lv.label.toLowerCase()} from ${p.currentTitle}';
  if (j.salary != null) return 'Pay is listed: ${j.salary}';
  if (j.remote && remoteOpenTo(j.location, p.country)) return 'Remote and open to ${p.country.isEmpty ? 'you' : p.country}';
  if (_studios.any((s) => j.company.toLowerCase().contains(s))) return inCity(j.location, p.city) ? 'Well-known studio near you' : 'Well-known studio';
  return null;
}

const _studios = ['riot', 'epic', 'rockstar', 'ubisoft', 'supercell', 'roblox', '2k', 'krafton', 'scopely', 'naughty dog', 'insomniac', 'bungie', 'gameloft', 'voodoo'];

/// Weaker matches are noise (e.g. a senior QA role for an SDE-1 search) and are left out.
const minScore = 30;

/// Matching jobs, best first, with duplicates from different sources merged.
List<JobMatch> rankJobs(Iterable<Job> jobs, JobProfile p, {DateTime? now}) {
  final seen = <String>{};
  final out = <JobMatch>[];
  for (final j in jobs) {
    if (!seen.add(j.dedupKey)) continue;
    final m = matchJob(j, p, now: now);
    if (m != null && m.score >= minScore) out.add(m);
  }
  return out..sort((a, b) => b.score != a.score ? b.score.compareTo(a.score) : (b.job.posted ?? DateTime(2000)).compareTo(a.job.posted ?? DateTime(2000)));
}

/// Skills the user lacks that most strong matches ask for, as (skill, share of those jobs).
List<(String, double)> skillGaps(List<JobMatch> matches, {int top = 6}) {
  final strong = matches.where((m) => m.score >= 45).toList();
  if (strong.length < 3) return const [];
  final counts = <String, int>{};
  for (final m in strong) {
    for (final s in m.missing) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
  }
  final ranked = counts.entries.where((e) => e.value >= 2 && e.value / strong.length >= 0.1).toList()..sort((a, b) => b.value.compareTo(a.value));
  return [for (final e in ranked.take(top)) (e.key, e.value / strong.length)];
}

/// A short plan built from the results alone, for when the cloud brain is off.
String quickPlan(JobProfile p, List<JobMatch> matches, List<(String, double)> gaps) {
  final top = matches.take(3).map((m) => '${m.job.title} at ${m.job.company}').toList();
  final steps = <String>[
    if (top.isNotEmpty) 'Apply first to: ${top.join('; ')}.',
    if (gaps.isNotEmpty) 'Learn ${gaps.first.$1} this month: ${(gaps.first.$2 * 100).round()}% of your best matches ask for it.',
    if (p.skills.length < 5) 'Add more of your skills to your profile so Buddy can match you better.',
    if (matches.any((m) => m.opportunity != null)) 'Look at "Better opportunities" above: each one is a step up from where you are.',
    'Build one small ${p.gameFocus ? 'game or gameplay feature' : 'project'} that shows ${gaps.isEmpty ? 'your best skill' : gaps.first.$1} and link it in every application.',
  ];
  return steps.map((s) => '• $s').join('\n');
}
