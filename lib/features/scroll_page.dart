import 'package:flutter/material.dart';

import '../core/native.dart';
import 'ui.dart';

/// System/launcher packages aren't "screen time" the user chose.
bool _isSystemNoise(Map a) {
  final pkg = (a['pkg'] as String?) ?? '';
  return pkg == 'com.android.systemui' || pkg.contains('launcher') || pkg.contains('nexuslauncher') || pkg == 'android';
}

class ScrollPage extends StatefulWidget {
  final bool embedded;
  const ScrollPage({super.key, this.embedded = false});
  @override
  State<ScrollPage> createState() => _ScrollPageState();
}

class _ScrollPageState extends State<ScrollPage> {
  List<Map> _days = [];
  Map? _usage;
  Map<String, dynamic> _perm = {};
  Map<String, dynamic> _settings = {'nudgeEnabled': true, 'nudgeEvery': 30, 'reelLimit': 150};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Future.wait([Native.scrollStats(7), Native.usageToday(), Native.permissions(), Native.getScrollSettings()]);
    if (!mounted) return;
    setState(() {
      _days = r[0] as List<Map>;
      _usage = r[1] as Map?;
      _perm = r[2] as Map<String, dynamic>;
      _settings = r[3] as Map<String, dynamic>;
      _loaded = true;
    });
  }

  Future<void> _set(Map<String, dynamic> s) async {
    setState(() => _settings.addAll(s));
    await Native.setScrollSettings(s);
  }

  Future<void> _openSettings() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => StatefulBuilder(
          builder: (context, set) {
            void upd(Map<String, dynamic> s) {
              set(() {});
              _set(s);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Scroll nudges', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Text('Vibration only, never a sound'),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Nudge me while binge-scrolling'),
                  value: _settings['nudgeEnabled'],
                  onChanged: (v) => upd({'nudgeEnabled': v}),
                ),
                ListTile(
                  title: Text('After every ${_settings['nudgeEvery']} reels in a row'),
                  subtitle: Slider(
                    value: (_settings['nudgeEvery'] as int).toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 9,
                    onChanged: _settings['nudgeEnabled'] ? (v) => set(() => _settings['nudgeEvery'] = v.round()) : null,
                    onChangeEnd: (v) => upd({'nudgeEvery': v.round()}),
                  ),
                ),
                ListTile(
                  title: Text('Daily limit: ${_settings['reelLimit']} reels (≈ ${((_settings['reelLimit'] as int) / 3).round()} min)'),
                  subtitle: Slider(
                    value: (_settings['reelLimit'] as int).toDouble(),
                    min: 20,
                    max: 500,
                    divisions: 48,
                    onChanged: (v) => set(() => _settings['reelLimit'] = v.round()),
                    onChangeEnd: (v) => upd({'reelLimit': v.round()}),
                  ),
                ),
              ]),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final today = _days.isNotEmpty ? _days.first : null;
    final reels = today == null ? 0 : Native.reelsOn(today);
    final limit = _settings['reelLimit'] as int;
    final apps = today == null ? <String, dynamic>{} : Map<String, dynamic>.from(today['apps']);
    final svMinutes = Map<String, dynamic>.from(_usage?['shortVideo'] ?? {});
    final appNames = {...apps.keys, ...svMinutes.keys}.toList()
      ..sort((a, b) => ((apps[b]?['reels'] ?? 0) as int).compareTo((apps[a]?['reels'] ?? 0) as int));
    final over = reels > limit;
    final statusColor = over ? Colors.red : reels > limit * 0.7 ? Colors.orange : Colors.green;
    final top = ((_usage?['top'] as List?) ?? []).cast<Map>().where((a) => !_isSystemNoise(a)).toList();
    final totalMin = top.fold<int>(0, (a, x) => a + (x['minutes'] as int));

    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Scroll'),
              actions: [IconButton(onPressed: _openSettings, icon: const Icon(Icons.tune), tooltip: 'Nudge settings')],
            ),
      floatingActionButton: widget.embedded ? FloatingActionButton.small(onPressed: _openSettings, tooltip: 'Nudge settings', child: const Icon(Icons.tune)) : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: pagePadding, children: [
          if (_perm['accessibility'] == false)
            InfoBanner(
              icon: Icons.accessibility_new,
              text: 'Turn on "Buddy scroll tracker" to count Reels & Shorts.',
              action: 'Turn on',
              onTap: () => Native.open('accessibility'),
            ),
          if (_perm['usage'] == false)
            InfoBanner(icon: Icons.timer_outlined, text: 'Allow Usage access to see minutes per app.', action: 'Allow', onTap: () => Native.open('usage')),
          HeroCard(
            color: over ? cs.errorContainer : null,
            child: Column(children: [
              Text('$reels', style: tt.displayLarge?.copyWith(fontWeight: FontWeight.w800, height: 1)),
              const SizedBox(height: 4),
              Text('reels & shorts today', style: tt.titleMedium),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: (reels / limit).clamp(0, 1), minHeight: 12, borderRadius: BorderRadius.circular(8), color: statusColor),
              const SizedBox(height: 8),
              Row(children: [
                Text(over ? '${reels - limit} over limit' : '${limit - reels} left', style: TextStyle(color: statusColor, fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('limit $limit · ≈ ${(reels / 3).round()} min watched', style: tt.bodySmall),
              ]),
            ]),
          ),
          const SectionTitle('By app'),
          AppCard(
            padding: appNames.isEmpty ? const EdgeInsets.all(16) : const EdgeInsets.symmetric(vertical: 4),
            child: appNames.isEmpty
                ? EmptyState(
                    emoji: _loaded ? '🎉' : '⏳',
                    title: _loaded ? 'No scrolling yet today' : 'Loading…',
                    subtitle: 'Reels, Shorts and TikTok-style swipes show up here.',
                  )
                : Column(children: [
                    for (final name in appNames)
                      ListTile(
                        leading: CircleAvatar(child: Text(name[0])),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${apps[name]?['reels'] ?? 0} reels · ${apps[name]?['feed'] ?? 0} feed scrolls'),
                        trailing: Text('${svMinutes[name] ?? 0} min', style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                  ]),
          ),
          const SectionTitle('Last 7 days'),
          AppCard(
            child: WeekBars(
              data: [
                for (final d in _days.reversed)
                  (weekdayShort(DateTime.parse(d['date'])), Native.reelsOn(d)),
              ],
              goal: limit,
              color: Colors.indigoAccent,
              overIsBad: true,
              emptyText: 'Your daily reel counts will build up here.',
            ),
          ),
          if (_usage != null && top.isNotEmpty) ...[
            SectionTitle('Screen time today', trailing: Text('${totalMin ~/ 60}h ${totalMin % 60}m', style: tt.titleSmall)),
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(children: [
                for (final a in top)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(a['label'], maxLines: 1, overflow: TextOverflow.ellipsis)),
                      Expanded(
                        flex: 4,
                        child: LinearProgressIndicator(
                          value: (a['minutes'] as int) / (top.first['minutes'] as int),
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      SizedBox(width: 56, child: Text('${a['minutes']} min', textAlign: TextAlign.right, style: tt.bodySmall)),
                    ]),
                  ),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
