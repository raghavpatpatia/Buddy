import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'learn_page.dart' show openLink;
import 'lessons.dart' show dayOfYear;

/// Small, finishable game-programming challenges: one a day.
const _challenges = [
  ('Camera shake', 'Add a trauma-based camera shake: trauma 0..1 decays over time, offset = maxShake × trauma² × noise.'),
  ('Coyote time', 'Let the player jump for 0.1 s after walking off a ledge. Then add jump buffering (press jump 0.1 s early).'),
  ('Object pool', 'Replace Instantiate/Destroy for bullets with a pool of 50. Measure GC allocations before/after.'),
  ('Tween a button', 'Make a button "pop": scale 1 → 1.15 → 1 with ease-out-back on tap, plus a tiny haptic.'),
  ('Grid pathfinding', 'Implement BFS on a 10×10 grid with walls. Bonus: upgrade to A* with Manhattan distance.'),
  ('Save system', 'Serialize player progress to JSON with a version number, and write a migration for v1 → v2.'),
  ('Match-3 detector', 'Given an 8×8 board, find all horizontal & vertical runs of 3+ in one pass.'),
  ('Fixed timestep', 'Convert an update loop to a fixed 60 Hz physics step with an accumulator and render interpolation.'),
  ('Health bar juice', 'Damage: bar snaps to new value, a white "ghost" bar drains after 0.4 s, number pops.'),
  ('Spatial hash', 'Bucket 1000 moving circles into a spatial hash; only test collisions within neighbouring cells.'),
  ('Finite state machine', 'Write an enemy FSM: Patrol → Chase (sees player) → Attack (in range) → Return.'),
  ('Procedural dungeon', 'Generate rooms with BSP splitting, connect them with L-shaped corridors.'),
  ('Shader warm-up', 'Write a fragment shader that makes a sprite flash white on hit (mix with uniform 0..1).'),
  ('Profiler hunt', 'Open your current game in the profiler, find the single most expensive function, make it 2× faster.'),
];

const _tools = <(String, List<(String, String, String)>)>[
  ('Every day', [
    ('DevDocs', 'All API docs offline in one search', 'https://devdocs.io'),
    ('roadmap.sh', 'Skill roadmaps (incl. game developer)', 'https://roadmap.sh/game-developer'),
    ('Excalidraw', 'Quick hand-drawn diagrams', 'https://excalidraw.com'),
    ('regex101', 'Build & debug regex', 'https://regex101.com'),
    ('crontab.guru', 'Understand cron expressions', 'https://crontab.guru'),
    ('Squoosh', 'Compress images/sprites in the browser', 'https://squoosh.app'),
  ]),
  ('Learn game programming (free)', [
    ('Game Programming Patterns', 'Free book: loop, pools, state, ECS', 'https://gameprogrammingpatterns.com'),
    ('Red Blob Games', 'Interactive pathfinding, hex grids, noise', 'https://www.redblobgames.com'),
    ('The Book of Shaders', 'Learn fragment shaders step by step', 'https://thebookofshaders.com'),
    ('Learn OpenGL', 'Graphics programming from scratch', 'https://learnopengl.com'),
    ('Cocos Creator docs', 'Engine manual & API', 'https://docs.cocos.com/creator/manual/en/'),
    ('GDC Vault (free talks)', 'Hundreds of free GDC talks', 'https://gdcvault.com/free'),
  ]),
  ('Practise & play', [
    ('Shadertoy', 'Explore & remix live shaders', 'https://www.shadertoy.com'),
    ('itch.io game jams', 'Join a jam this weekend', 'https://itch.io/jams'),
    ('Exercism', 'Free mentored coding exercises', 'https://exercism.org'),
    ('Advent of Code', 'Puzzle-a-day (great in December)', 'https://adventofcode.com'),
  ]),
  ('Free assets', [
    ('Kenney', 'Thousands of CC0 game assets', 'https://kenney.nl/assets'),
    ('OpenGameArt', 'Sprites, music, SFX', 'https://opengameart.org'),
    ('Freesound', 'Sound effects library', 'https://freesound.org'),
    ('Lospec palettes', 'Pixel-art colour palettes', 'https://lospec.com/palette-list'),
  ]),
];

class ToolboxPage extends StatefulWidget {
  const ToolboxPage({super.key});
  @override
  State<ToolboxPage> createState() => _ToolboxPageState();
}

class _ToolboxPageState extends State<ToolboxPage> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (title, desc) = _challenges[dayOfYear() % _challenges.length];
    final done = Store.raw.getString('challenge_done') == dayKey();
    return ListView(padding: pagePadding, children: [
      Card(
        color: cs.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('🧩 Daily game-dev challenge', style: tt.labelLarge),
            const SizedBox(height: 6),
            Text(title, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(desc, style: tt.bodyLarge?.copyWith(height: 1.4)),
            const SizedBox(height: 14),
            Row(children: [
              Text('~30–60 min · +25 XP', style: tt.bodySmall),
              const Spacer(),
              done
                  ? const Chip(avatar: Icon(Icons.check, color: Colors.green), label: Text('Done today'))
                  : FilledButton.icon(
                      onPressed: () async {
                        HapticFeedback.mediumImpact();
                        await Store.raw.setString('challenge_done', dayKey());
                        await Store.addXp(25);
                        setState(() {});
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('I did it'),
                    ),
            ]),
          ]),
        ),
      ),
      for (final (section, items) in _tools) ...[
        SectionTitle(section),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            for (final (name, what, url) in items)
              ListTile(
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(what),
                trailing: const Icon(Icons.open_in_new, size: 18),
                onTap: () => openLink(url),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 8),
      Text('All free. Opens in your browser.', textAlign: TextAlign.center, style: tt.bodySmall),
    ]);
  }
}
