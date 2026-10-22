import '../model/job_profile.dart';
import '../model/roles.dart';

/// A job site Buddy can't search directly, opened with the search already filled in.
typedef Platform = ({String name, String emoji, String url});

String _q(String s) => Uri.encodeQueryComponent(s);
String _slug(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

const _indeedHosts = {
  'india': 'in.indeed.com', 'united kingdom': 'uk.indeed.com', 'canada': 'ca.indeed.com', 'australia': 'au.indeed.com',
  'singapore': 'sg.indeed.com', 'united arab emirates': 'ae.indeed.com',
};

/// Wellfound uses older city names in its URLs.
const _wellfoundCity = {'bengaluru': 'bangalore', 'gurugram': 'gurgaon', 'new york': 'new-york-city'};

/// Search links for the big job sites, using the profile's role, focus and place.
List<Platform> platformLinks(JobProfile p) {
  final q = p.searchPhrase;
  final place = switch (p.scope) {
    JobScope.near => p.city.isNotEmpty ? p.city : p.country,
    JobScope.country => p.country,
    JobScope.remote || JobScope.worldwide => '',
  };
  final remote = p.scope == JobScope.remote;
  final india = p.country.toLowerCase() == 'india';
  final lvl = p.targetLevel;
  final linkedInLevel = switch (lvl) { Level.intern => '1', Level.entry => '2', Level.mid => '3,4', _ => '4' };
  final city = p.city.toLowerCase();
  return [
    (
      name: 'LinkedIn',
      emoji: '💼',
      url: 'https://www.linkedin.com/jobs/search/?keywords=${_q(q)}&location=${_q(place.isEmpty ? 'Worldwide' : place)}&f_E=$linkedInLevel${remote ? '&f_WT=2' : ''}',
    ),
    if (india)
      (
        name: 'Naukri',
        emoji: '🇮🇳',
        url: 'https://www.naukri.com/${_slug(q)}-jobs${p.scope == JobScope.near && p.city.isNotEmpty ? '-in-${_slug(p.city)}' : ''}${remote ? '?wfhType=2' : ''}',
      ),
    (
      name: 'Indeed',
      emoji: '🔎',
      url: 'https://${_indeedHosts[p.country.toLowerCase()] ?? 'www.indeed.com'}/jobs?q=${_q(q)}&l=${_q(remote ? 'Remote' : place)}',
    ),
    (
      name: 'Google Jobs',
      emoji: '🌐',
      url: 'https://www.google.com/search?q=${_q('$q jobs ${remote ? 'remote' : place.isEmpty ? '' : 'in $place'}'.trim())}&udm=8',
    ),
    if (p.gameFocus) (name: 'Hitmarker', emoji: '🎮', url: 'https://hitmarker.net/jobs?keyword=${_q(q)}'),
    if (p.gameFocus) (name: 'Work With Indies', emoji: '🕹️', url: 'https://www.workwithindies.com/'),
    (
      name: 'Wellfound',
      emoji: '🚀',
      url: 'https://wellfound.com/role/${p.scope == JobScope.near && city.isNotEmpty ? 'l/${_slug(q)}/${_wellfoundCity[city] ?? _slug(city)}' : _slug(q)}',
    ),
    (
      name: 'Glassdoor',
      emoji: '🏢',
      url: 'https://www.glassdoor.${india ? 'co.in' : 'com'}/Job/jobs.htm?sc.keyword=${_q(q)}&locKeyword=${_q(place)}',
    ),
  ];
}
