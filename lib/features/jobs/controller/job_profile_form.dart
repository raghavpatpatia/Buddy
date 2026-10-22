import '../../../core/arch/safe_notifier.dart';
import '../data/locate.dart';
import '../model/job.dart';
import '../model/job_profile.dart';
import 'jobs_controller.dart';

/// Draft of the job profile while the user edits it; nothing is saved until [build].
class JobProfileForm extends SafeNotifier {
  JobProfileForm(JobProfile p, {this._locate = _askLocation})
      : roles = [...p.roles],
        skills = [...p.skills],
        years = p.years,
        scope = p.scope,
        _base = p;

  final JobProfile _base;
  final Locate _locate;
  final List<String> roles, skills;
  int years;
  JobScope scope;
  bool locating = false;

  static const maxSkills = 30;

  void toggleRole(String id) {
    if (roles.contains(id)) {
      if (roles.length > 1) roles.remove(id);
    } else {
      roles.add(id);
    }
    notifyListeners();
  }

  /// Adds one or more comma-separated skills, ignoring blanks and duplicates.
  void addSkills(String text) {
    for (final raw in text.split(RegExp(r'[,;\n]'))) {
      final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (s.isEmpty || s.length > 40 || skills.length >= maxSkills) continue;
      if (skills.any((x) => x.toLowerCase() == s.toLowerCase())) continue;
      skills.add(s);
    }
    notifyListeners();
  }

  void removeSkill(String s) {
    skills.remove(s);
    notifyListeners();
  }

  void setYears(int v) {
    years = v.clamp(0, 40);
    notifyListeners();
  }

  void setScope(JobScope s) {
    scope = s;
    notifyListeners();
  }

  /// Known skills not added yet, the ones that fit the focus first.
  List<String> suggestions(String focus) {
    final game = RegExp(r'gam', caseSensitive: false).hasMatch(focus);
    final all = [for (final (n, _) in skillVocab) n];
    if (game) all.sortByFirst(const ['C++', 'C#', 'Unity', 'Unreal', 'Shaders', 'Multiplayer', 'Data structures', 'Git', 'Perforce', 'Lua']);
    final have = {for (final s in skills) s.toLowerCase()};
    return all.where((s) => !have.contains(s.toLowerCase())).take(12).toList();
  }

  /// City and country near the user, or null when unknown.
  Future<(String, String)?> detect() async {
    locating = true;
    notifyListeners();
    final r = await _locate();
    locating = false;
    notifyListeners();
    return r.$1.isEmpty && r.$2.isEmpty ? null : r;
  }

  JobProfile build({required String title, required String focus, required String city, required String country}) => _base.copyWith(
        currentTitle: title.trim(),
        focus: focus.trim(),
        city: city.trim(),
        country: country.trim(),
        years: years,
        roles: [...roles],
        skills: [...skills],
        scope: scope,
      );
}

extension on List<String> {
  /// Moves [first] (in that order) to the front, keeping the rest in place.
  void sortByFirst(List<String> first) {
    final front = [for (final f in first) if (contains(f)) f];
    removeWhere(front.contains);
    insertAll(0, front);
  }
}

Future<(String, String)> _askLocation() => nearUser(ask: true);
