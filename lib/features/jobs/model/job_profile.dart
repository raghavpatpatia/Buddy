import 'roles.dart';

/// How far from home to look.
enum JobScope { near, country, remote, worldwide }

/// What the user told Buddy about their career; drives search and ranking.
class JobProfile {
  final String currentTitle, focus, city, country;
  final int years;
  final List<String> skills, roles;
  final JobScope scope;

  /// False until the user has saved the profile once.
  final bool setUp;

  const JobProfile({
    this.currentTitle = '',
    this.years = 0,
    this.skills = const [],
    this.roles = const ['sde1'],
    this.focus = 'Game development',
    this.city = '',
    this.country = '',
    this.scope = JobScope.near,
    this.setUp = false,
  });

  List<RoleOption> get targetRoles => [for (final id in roles) ?roleById(id)];

  /// The user's current seniority: from their title, else their years.
  Level get currentLevel => levelOf(currentTitle) ?? levelForYears(years);

  /// The seniority they're aiming for: the lowest explicit target level, else their current one.
  Level get targetLevel {
    final explicit = [for (final r in targetRoles) ?r.level]..sort((a, b) => a.index.compareTo(b.index));
    return explicit.firstOrNull ?? currentLevel;
  }

  bool get gameFocus => RegExp(r'\bgam(e|es|ing)\b', caseSensitive: false).hasMatch(focus);

  /// Words from the focus that a matching job mentions (e.g. "game", "gaming", "unity").
  List<String> get focusTerms {
    final words = focus.toLowerCase().split(RegExp(r'[^a-z0-9+#]+')).where((w) => w.length > 2 && !_stop.contains(w)).toList();
    if (gameFocus) words.addAll(['game', 'games', 'gaming', 'studio', 'unity', 'unreal']);
    return words.toSet().toList();
  }

  /// Short phrase for job-site searches, e.g. "game developer" or "unity developer".
  String get searchPhrase {
    final r = targetRoles.firstOrNull ?? roleOptions.first;
    if (!r.generic) return r.search;
    if (gameFocus) return r.level == Level.intern ? 'game developer intern' : 'game developer';
    final f = focusTerms.firstOrNull;
    return f == null ? r.search : '$f ${r.search}';
  }

  /// One keyword for APIs that search a single tag.
  String get keyword => gameFocus ? 'game' : (focusTerms.firstOrNull ?? searchPhrase.split(' ').last);

  String get placeLabel => [city, country].where((s) => s.isNotEmpty).join(', ');

  String scopeLabel(JobScope s) => switch (s) {
        JobScope.near => city.isEmpty ? 'Near me' : city,
        JobScope.country => country.isEmpty ? 'My country' : country,
        JobScope.remote => 'Remote',
        JobScope.worldwide => 'Anywhere',
      };

  JobProfile copyWith({
    String? currentTitle,
    int? years,
    List<String>? skills,
    List<String>? roles,
    String? focus,
    String? city,
    String? country,
    JobScope? scope,
    bool? setUp,
  }) =>
      JobProfile(
        currentTitle: currentTitle ?? this.currentTitle,
        years: years ?? this.years,
        skills: skills ?? this.skills,
        roles: roles ?? this.roles,
        focus: focus ?? this.focus,
        city: city ?? this.city,
        country: country ?? this.country,
        scope: scope ?? this.scope,
        setUp: setUp ?? this.setUp,
      );

  Map<String, dynamic> toJson() => {
        'title': currentTitle, 'years': years, 'skills': skills, 'roles': roles, 'focus': focus,
        'city': city, 'country': country, 'scope': scope.name, 'setUp': setUp,
      };

  static JobProfile fromJson(Map j) {
    final roles = [for (final r in (j['roles'] as List? ?? const [])) if (roleById('$r') != null) '$r'];
    return JobProfile(
      currentTitle: j['title'] as String? ?? '',
      years: (j['years'] as num?)?.toInt() ?? 0,
      skills: [for (final s in (j['skills'] as List? ?? const [])) '$s'],
      roles: roles.isEmpty ? const ['sde1'] : roles,
      focus: j['focus'] as String? ?? 'Game development',
      city: j['city'] as String? ?? '',
      country: j['country'] as String? ?? '',
      scope: JobScope.values.asNameMap()[j['scope']] ?? JobScope.near,
      setUp: j['setUp'] == true,
    );
  }
}

const _stop = {'and', 'the', 'for', 'with', 'development', 'developer', 'jobs', 'job', 'work', 'role', 'roles', 'industry', 'company', 'companies'};
