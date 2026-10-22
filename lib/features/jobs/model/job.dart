/// One job posting from any source, kept small so results can be cached and saved.
class Job {
  final String id, title, company, location, url, source, summary;
  final bool remote;
  final DateTime? posted;
  final String? salary, level;

  /// Known skills found in the full posting (see [skillVocab]).
  final List<String> skills;

  const Job({
    required this.id,
    required this.title,
    required this.company,
    required this.location,
    required this.url,
    required this.source,
    this.summary = '',
    this.remote = false,
    this.posted,
    this.salary,
    this.level,
    this.skills = const [],
  });

  /// Same role at the same company from two sources counts once.
  String get dedupKey => '${_norm(title)}|${_norm(company)}';

  Map<String, dynamic> toJson() => {
        'id': id, 't': title, 'c': company, 'l': location, 'u': url, 's': source, 'm': summary,
        'r': remote, 'p': posted?.toIso8601String(), 'pay': salary, 'lv': level, 'sk': skills,
      };

  static Job fromJson(dynamic j) => Job(
        id: j['id'],
        title: j['t'],
        company: j['c'],
        location: j['l'] ?? '',
        url: j['u'],
        source: j['s'] ?? '',
        summary: j['m'] ?? '',
        remote: j['r'] == true,
        posted: DateTime.tryParse(j['p'] ?? ''),
        salary: j['pay'],
        level: j['lv'],
        skills: [for (final s in (j['sk'] as List? ?? const [])) s as String],
      );
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Skills Buddy recognises in postings; the pattern is matched case-insensitively.
const skillVocab = <(String, String)>[
  ('C++', r'c\+\+'), ('C#', r'c#|\bcsharp\b'), ('Unity', r'\bunity(3d)?\b'), ('Unreal', r'\bunreal|\bue[45]\b'),
  ('Godot', r'\bgodot\b'), ('Python', r'\bpython\b'), ('Java', r'\bjava\b(?!script)'), ('Kotlin', r'\bkotlin\b'),
  ('Swift', r'\bswift\b'), ('Go', r'\bgolang\b'), ('Rust', r'\brust\b'), ('JavaScript', r'\bjavascript\b'),
  ('TypeScript', r'\btypescript\b'), ('React', r'\breact\b'), ('Node.js', r'\bnode\.?js\b'), ('Flutter', r'\bflutter\b'),
  ('Lua', r'\blua\b'), ('SQL', r'\bsql\b|postgres|mysql'), ('AWS', r'\baws\b'), ('GCP', r'\bgcp\b|google cloud'),
  ('Azure', r'\bazure\b'), ('Docker', r'\bdocker\b'), ('Kubernetes', r'\bkubernetes\b|\bk8s\b'), ('Linux', r'\blinux\b'),
  ('Git', r'\bgit\b'), ('Perforce', r'\bperforce\b'), ('OpenGL', r'\bopengl\b'), ('Vulkan', r'\bvulkan\b'),
  ('DirectX', r'\bdirectx\b|\bdx12\b'), ('Shaders', r'\bshaders?\b|\bhlsl\b|\bglsl\b'), ('Multiplayer', r'\bmultiplayer\b|netcode'),
  ('Networking', r'\bnetworking\b'), ('Blender', r'\bblender\b'), ('Maya', r'\bmaya\b'), ('Firebase', r'\bfirebase\b'),
  ('Redis', r'\bredis\b'), ('Kafka', r'\bkafka\b'), ('GraphQL', r'\bgraphql\b'), ('Machine learning', r'machine learning|\bml\b'),
  ('PyTorch', r'\bpytorch\b'), ('Figma', r'\bfigma\b'), ('CI/CD', r'\bci/cd\b|\bjenkins\b'), ('Data structures', r'data structures|algorithms'),
];

final _vocab = [for (final (name, p) in skillVocab) (name, RegExp(p, caseSensitive: false))];

/// Skill names from [skillVocab] that appear in [text].
List<String> findSkills(String text) => [for (final (name, re) in _vocab) if (re.hasMatch(text)) name];

/// Plain text from a posting's HTML, entities decoded and whitespace collapsed.
String plainText(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#x27;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&#x2F;', '/')
    .replaceAll('&hellip;', '…')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();
