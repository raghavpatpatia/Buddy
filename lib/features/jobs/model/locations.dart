import '../../astro/model/places.dart' show places;

/// Other names job sites use for the same city.
const _aliases = <String, List<String>>{
  'bengaluru': ['bangalore', 'bengaluru'],
  'gurugram': ['gurgaon', 'gurugram', 'delhi', 'ncr', 'noida'],
  'delhi': ['delhi', 'new delhi', 'ncr', 'noida', 'gurgaon', 'gurugram'],
  'noida': ['noida', 'delhi', 'ncr', 'gurgaon', 'gurugram'],
  'mumbai': ['mumbai', 'bombay', 'thane', 'navi mumbai'],
  'thane': ['thane', 'mumbai', 'navi mumbai'],
  'chennai': ['chennai', 'madras'],
  'kolkata': ['kolkata', 'calcutta'],
  'hyderabad': ['hyderabad', 'secunderabad'],
  'thiruvananthapuram': ['thiruvananthapuram', 'trivandrum'],
  'kochi': ['kochi', 'cochin'],
  'allahabad (prayagraj)': ['allahabad', 'prayagraj'],
  'mysuru': ['mysuru', 'mysore'],
  'mangaluru': ['mangaluru', 'mangalore'],
  'new york': ['new york', 'nyc', 'brooklyn'],
  'san francisco': ['san francisco', 'sf', 'bay area', 'san mateo', 'oakland'],
};

/// Words that mean "open to the whole world".
const _anywhere = ['worldwide', 'anywhere', 'global', 'world'];

/// Regions that include a country, for remote restrictions like "APAC" or "Asia".
const _regions = <String, List<String>>{
  'india': ['india', 'asia', 'apac', 'south asia'],
  'united states': ['united states', 'usa', 'us', 'u.s.', 'america', 'north america', 'americas'],
  'united kingdom': ['united kingdom', 'uk', 'england', 'europe', 'emea'],
  'canada': ['canada', 'north america', 'americas'],
  'singapore': ['singapore', 'asia', 'apac', 'southeast asia'],
  'united arab emirates': ['united arab emirates', 'uae', 'dubai', 'middle east', 'emea'],
  'australia': ['australia', 'apac', 'anz'],
};

String _lc(String s) => s.toLowerCase();

final _wordRes = <String, RegExp>{};

bool _hasWord(String text, String w) => _wordRes.putIfAbsent(w, () => RegExp('(^|[^a-z])${RegExp.escape(w)}([^a-z]|\$)')).hasMatch(text);

/// True when [location] is in or next to [city].
bool inCity(String location, String city) {
  if (city.isEmpty) return false;
  final l = _lc(location);
  return (_aliases[_lc(city)] ?? [_lc(city)]).any((a) => _hasWord(l, a));
}

/// True when [location] names [country] or one of its known cities.
bool inCountry(String location, String country) {
  if (country.isEmpty) return false;
  if (_hasWord(_lc(location), _lc(country))) return true;
  return places.any((p) => countryOfCity(p.$1) == country && inCity(location, p.$1));
}

/// True when someone in [country] can take a remote job restricted to [location].
bool remoteOpenTo(String location, String country) {
  final l = _lc(location).trim();
  if (l.isEmpty || l == 'remote' || _anywhere.any((w) => _hasWord(l, w))) return true;
  if (country.isEmpty) return false;
  return (_regions[_lc(country)] ?? [_lc(country)]).any((w) => _hasWord(l, w));
}

/// Country of a city in the offline place list (astro's places); India unless listed here.
String countryOfCity(String city) => const {
      'Kathmandu': 'Nepal', 'Dhaka': 'Bangladesh', 'Colombo': 'Sri Lanka', 'Karachi': 'Pakistan', 'Lahore': 'Pakistan',
      'Dubai': 'United Arab Emirates', 'Singapore': 'Singapore', 'London': 'United Kingdom', 'New York': 'United States',
      'San Francisco': 'United States', 'Toronto': 'Canada', 'Sydney': 'Australia',
    }[city] ??
    'India';

/// ISO code for the few APIs that filter by country.
String? countryCode(String country) => const {
      'india': 'in', 'united states': 'us', 'united kingdom': 'gb', 'canada': 'ca', 'singapore': 'sg',
      'united arab emirates': 'ae', 'australia': 'au', 'nepal': 'np', 'bangladesh': 'bd', 'sri lanka': 'lk', 'pakistan': 'pk',
    }[_lc(country)];
