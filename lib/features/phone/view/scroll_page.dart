import 'package:flutter/material.dart';

import '../../../core/native.dart';
import '../controller/scroll_stats_controller.dart';
import '../../../shared/ui.dart';

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
  final c = ScrollStatsController();

  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _openSettings() => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (_) => ListenableBuilder(
          listenable: c,
          builder: (context, _) {
            final settings = c.settings;
            void upd(Map<String, dynamic> s) => c.updateSettings(s);

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text('Scroll nudges', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const Text('Vibration only, never a sound'),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Nudge me while binge-scrolling'),
                  value: settings['nudgeEnabled'],
                  onChanged: (v) => upd({'nudgeEnabled': v}),
                ),
                ListTile(
                  title: Text('After every ${settings['nudgeEvery']} reels in a row'),
                  subtitle: Slider(
                    value: (settings['nudgeEvery'] as int).toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 9,
                    onChanged: settings['nudgeEnabled'] ? (v) => c.updateSettings({'nudgeEvery': v.round()}, save: false) : null,
                    onChangeEnd: (v) => upd({'nudgeEvery': v.round()}),
                  ),
                ),
                ListTile(
                  title: Text('Daily limit: ${settings['reelLimit']} reels (≈ ${((settings['reelLimit'] as int) / 3).round()} min)'),
                  subtitle: Slider(
                    value: (settings['reelLimit'] as int).toDouble(),
                    min: 20,
                    max: 500,
                    divisions: 48,
                    onChanged: (v) => c.updateSettings({'reelLimit': v.round()}, save: false),
                    onChangeEnd: (v) => upd({'reelLimit': v.round()}),
                  ),
                ),
              ]),
            );
          },
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final today = c.today;
    final reels = c.reelsToday;
    final limit = c.limit;
    final usage = c.usage;
    final apps = today == null ? <String, dynamic>{} : Map<String, dynamic>.from(today['apps']);
    final svMinutes = Map<String, dynamic>.from(usage?['shortVideo'] ?? {});
    final appNames = {...apps.keys, ...svMinutes.keys}.toList()
      ..sort((a, b) => ((apps[b]?['reels'] ?? 0) as int).compareTo((apps[a]?['reels'] ?? 0) as int));
    final over = reels > limit;
    final statusColor = over ? Colors.red : reels > limit * 0.7 ? Colors.orange : Colors.green;
    final top = ((usage?['top'] as List?) ?? []).cast<Map>().where((a) => !_isSystemNoise(a)).toList();
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
        onRefresh: c.load,
        child: ListView(padding: pagePadding, children: [
          if (c.trackerOff)
            InfoBanner(
              icon: Icons.accessibility_new,
              text: 'Turn on "Buddy scroll tracker" to count Reels & Shorts.',
              action: 'Turn on',
              onTap: () => Native.open('accessibility'),
            ),
          if (c.killerStruck)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your phone keeps switching tracking off', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Its ${c.killer} battery manager closed Buddy ${c.killerTimes == 1 ? 'once' : '${c.killerTimes} times'}, and Android turns '
                  'the scroll tracker off each time. Open ${c.killer}, allow Buddy (switch it off for Buddy or add it to the allowed list), '
                  'then turn the tracker back on.',
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  FilledButton.tonal(onPressed: () => Native.open('killer'), child: Text('Open ${c.killer}')),
                  TextButton(onPressed: c.ackKiller, child: const Text('Done')),
                ]),
              ]),
            ),
          if (c.usageOff)
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
                    emoji: c.loaded ? '🎉' : '⏳',
                    title: c.loaded ? 'No scrolling yet today' : 'Loading…',
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
                for (final d in c.days.reversed)
                  (weekdayShort(DateTime.parse(d['date'])), Native.reelsOn(d)),
              ],
              goal: limit,
              color: Colors.indigoAccent,
              overIsBad: true,
              emptyText: 'Your daily reel counts will build up here.',
            ),
          ),
          if (usage != null && top.isNotEmpty) ...[
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
