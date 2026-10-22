/// Seniority, lowest first, so levels can be compared by index.
enum Level { intern, entry, mid, senior, lead }

extension LevelLabel on Level {
  String get label => const ['Intern', 'Entry level', 'Mid level', 'Senior', 'Lead'][index];
}

/// A role the user can target: title keywords to match and the phrase used to search job sites.
class RoleOption {
  final String id, label, search;
  final List<String> keywords;

  /// Set for seniority roles (SDE-1, SDE-2…); other roles take the level from experience.
  final Level? level;

  /// Generic engineering roles take their domain from the user's focus (e.g. "game developer").
  final bool generic;
  const RoleOption(this.id, this.label, this.search, this.keywords, {this.level, this.generic = false});
}

const _swe = ['software engineer', 'software developer', 'sde', 'developer', 'engineer', 'programmer'];

const roleOptions = <RoleOption>[
  RoleOption('sde1', 'SDE-1', 'software engineer', _swe, level: Level.entry, generic: true),
  RoleOption('sde2', 'SDE-2', 'software engineer', _swe, level: Level.mid, generic: true),
  RoleOption('senior', 'Senior engineer', 'senior software engineer', _swe, level: Level.senior, generic: true),
  RoleOption('intern', 'Internship', 'intern', ['intern', 'internship', 'trainee'], level: Level.intern, generic: true),
  RoleOption('gameplay', 'Gameplay programmer', 'gameplay programmer', ['gameplay', 'game programmer', 'game developer', 'game engineer', 'game dev']),
  RoleOption('unity', 'Unity developer', 'unity developer', ['unity']),
  RoleOption('unreal', 'Unreal developer', 'unreal developer', ['unreal', 'ue5', 'ue4']),
  RoleOption('graphics', 'Graphics / engine', 'graphics programmer', ['graphics', 'rendering', 'engine programmer', 'engine developer', 'shader']),
  RoleOption('backend', 'Backend', 'backend engineer', ['backend', 'back-end', 'back end', 'server', 'api']),
  RoleOption('frontend', 'Frontend', 'frontend developer', ['frontend', 'front-end', 'front end', 'react', 'web developer', 'ui engineer']),
  RoleOption('fullstack', 'Full-stack', 'full stack developer', ['full stack', 'full-stack', 'fullstack']),
  RoleOption('mobile', 'Mobile', 'mobile developer', ['android', 'ios', 'mobile', 'flutter']),
  RoleOption('qa', 'QA / tester', 'qa engineer', ['qa', 'quality assurance', 'tester', 'test engineer', 'sdet']),
  RoleOption('techart', 'Technical artist', 'technical artist', ['technical artist', 'tech artist']),
  RoleOption('designer', 'Game designer', 'game designer', ['game designer', 'level designer', 'systems designer', 'designer']),
  RoleOption('devops', 'DevOps / SRE', 'devops engineer', ['devops', 'sre', 'site reliability', 'platform engineer', 'infrastructure']),
  RoleOption('data', 'Data / ML', 'machine learning engineer', ['machine learning', 'ml engineer', 'data scientist', 'data engineer', 'ai engineer']),
  RoleOption('pm', 'Product manager', 'product manager', ['product manager', 'product owner']),
  RoleOption('producer', 'Producer', 'game producer', ['producer']),
];

RoleOption? roleById(String id) => roleOptions.where((r) => r.id == id).firstOrNull;

final _lead = RegExp(r'\b(lead|principal|staff|director|head|engineering manager|architect|vp)\b', caseSensitive: false);
final _senior = RegExp(r'\b(senior|sr\.?|iii|sde[- ]?3|level 3)\b', caseSensitive: false);
final _mid = RegExp(r'\b(ii|sde[- ]?2|mid[- ]level|intermediate|level 2)\b', caseSensitive: false);
final _entry = RegExp(r'\b(junior|jr\.?|entry[- ]level|graduate|grad|associate|new grad|sde[- ]?1|engineer i|developer i|programmer i|level 1|fresher)\b', caseSensitive: false);
final _intern = RegExp(r'\b(intern|internship|trainee|apprentice)\b', caseSensitive: false);

/// Seniority implied by a title (or a source's level hint); null when it doesn't say.
Level? levelOf(String title, [String? hint]) {
  final t = '$title ${hint ?? ''}';
  if (_intern.hasMatch(t)) return Level.intern;
  if (_lead.hasMatch(t)) return Level.lead;
  if (_senior.hasMatch(t)) return Level.senior;
  if (_mid.hasMatch(t)) return Level.mid;
  if (_entry.hasMatch(t)) return Level.entry;
  return null;
}

/// Level from years of experience when the title doesn't say.
Level levelForYears(int years) => years < 3
    ? Level.entry
    : years < 6
        ? Level.mid
        : years < 10
            ? Level.senior
            : Level.lead;
