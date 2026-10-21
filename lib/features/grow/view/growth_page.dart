import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/bot_face.dart';
import '../controller/growth_controller.dart';
import '../data/growth_service.dart';
import '../model/lessons.dart';
import '../model/news.dart';
import '../controller/courses_controller.dart';
import 'courses_view.dart';
import 'learn_page.dart';
import 'math_card.dart';

/// Opens an article, then (when you come back) asks for a one-line takeaway. Writing it is what counts as "read".
Future<void> readAndReflect(BuildContext context, NewsItem n) async {
  final opened = DateTime.now();
  final back = Completer<void>();
  final listener = AppLifecycleListener(onResume: () {
    if (!back.isCompleted) back.complete();
  });
  await openLink(n.link);
  await back.future.timeout(const Duration(hours: 2), onTimeout: () {});
  listener.dispose();
  if (!context.mounted) return;
  final secs = DateTime.now().difference(opened).inSeconds;
  final note = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _TakeawaySheet(item: n, quick: secs < 20),
  );
  if (note == null || note.trim().isEmpty) return;
  await GrowthController.saveTakeaway(n, note);
  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Takeaway saved · +10 XP 📰')));
}

/// Asks for a one-line takeaway after reading an article.
class _TakeawaySheet extends StatefulWidget {
  final NewsItem item;
  final bool quick;
  const _TakeawaySheet({required this.item, required this.quick});
  @override
  State<_TakeawaySheet> createState() => _TakeawaySheetState();
}

class _TakeawaySheetState extends State<_TakeawaySheet> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final ok = _c.text.trim().split(RegExp(r'\s+')).length >= 4;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('What did you learn? ✍️', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(widget.item.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
        if (widget.quick) ...[
          const SizedBox(height: 8),
          Text('That was quick 👀 Skimmed it? Go back and read properly for the best takeaway.', style: tt.bodySmall?.copyWith(color: Colors.orange.shade800)),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _c,
          autofocus: true,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(hintText: 'One sentence in your own words…', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: ok ? () => Navigator.pop(context, _c.text) : null,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          child: Text(ok ? 'Save takeaway' : 'Write at least a few words'),
        ),
      ]),
    );
  }
}

/// Full-screen daily growth check. When [forced], it can't be dismissed except by finishing or taking the penalty.
class GrowthGatePage extends StatefulWidget {
  final bool forced;
  const GrowthGatePage({super.key, this.forced = false});
  @override
  State<GrowthGatePage> createState() => _GrowthGatePageState();
}

class _GrowthGatePageState extends State<GrowthGatePage> {
  final c = GrowthController();

  @override
  void initState() {
    super.initState();
    c.loadHeadlines();
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  Future<void> _skip() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Skip today?'),
        content: Text('You lose ${c.penaltyXp} XP and your ${c.streak}-day growth streak resets. '
            'Just one lesson and one story takes ~10 minutes.'),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('Okay, I’ll do it')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Take the penalty')),
        ],
      ),
    );
    if (ok != true) return;
    await c.skip();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final learn = c.learnDone, news = c.newsDone;
    final done = c.done;
    final s = c.suggested;
    final headlines = c.state.data;
    return PopScope(
      canPop: !widget.forced || done,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.forced || done,
          title: const Text('Growth check'),
        ),
        body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Center(child: BotFace(mood: done ? 1 : (learn || news ? 0.4 : -0.2), size: 120)),
          Text(
            done ? 'You grew today! 🌱' : '2 small things, ~10 minutes',
            textAlign: TextAlign.center,
            style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            done
                ? '+40 XP · growth streak ${c.streak} 🔥'
                : 'One thing learned + one story understood, every day. That’s how you get to build anything.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium,
          ),
          const SizedBox(height: 16),
          _step(
            context,
            n: 1,
            done: learn,
            title: 'Learn one thing',
            subtitle: learn ? 'Done ✓' : 'Today’s pick: ${s.emoji} ${s.name}: ${s.lessons[todaysIndex(s)].title}',
            child: learn
                ? null
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await openLessonSheet(context, s);
                        c.refresh();
                      },
                      icon: const Icon(Icons.auto_stories),
                      label: const Text('Start lesson (2 min)'),
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () async {
                            await showModalBottomSheet(context: context, isScrollControlled: true, useSafeArea: true, builder: (_) => const MathSheet(daily: true));
                            c.refresh();
                          },
                          child: const Text('or today’s maths'),
                        ),
                      ),
                      if (CoursesController().anyActive)
                        Expanded(
                          child: TextButton(
                            onPressed: () async {
                              await showModalBottomSheet(
                                context: context,
                                isScrollControlled: true,
                                useSafeArea: true,
                                builder: (_) => const SingleChildScrollView(padding: EdgeInsets.all(16), child: MyCourses()),
                              );
                              c.refresh();
                            },
                            child: const Text('or a course unit'),
                          ),
                        ),
                    ]),
                  ]),
          ),
          _step(
            context,
            n: 2,
            done: news,
            title: 'Read one important story',
            subtitle: news ? 'Takeaway: “${c.lastTakeaway ?? ''}”' : 'Read it, then write one line in your own words.',
            child: news
                ? null
                : headlines == null
                    ? const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
                    : headlines.isEmpty
                        ? const Text('Offline: connect to load today’s headlines.')
                        : Column(children: [
                            for (final (i, h) in headlines.indexed)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: Text(['🇮🇳', '🌍', '💻'][i], style: const TextStyle(fontSize: 22)),
                                title: Text(h.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(h.source),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () async {
                                  await readAndReflect(context, h);
                                  c.refresh();
                                },
                              ),
                          ]),
          ),
          const SizedBox(height: 12),
          if (done)
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Done for today 🎉'),
            )
          else if (widget.forced)
            TextButton(
              onPressed: _skip,
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: Text('Skip & take penalty (−${c.penaltyXp} XP, streak resets)'),
            ),
        ]),
      ),
    );
  }

  Widget _step(BuildContext context, {required int n, required bool done, required String title, required String subtitle, Widget? child}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: done ? Colors.green.withValues(alpha: 0.12) : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: done ? Colors.green : cs.primaryContainer,
              child: done ? const Icon(Icons.check, color: Colors.white, size: 18) : Text('$n', style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
          if (child != null) ...[const SizedBox(height: 10), child],
        ]),
      ),
    );
  }
}

/// Home-screen card: today's 2 commitments at a glance.
class GrowthCard extends StatelessWidget {
  final VoidCallback onChanged;
  const GrowthCard({super.key, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final g = GrowthController();
    final learn = g.learnDone, news = g.newsDone;
    final done = g.done;
    final h = g.hour;
    Widget item(bool ok, String label) => Row(children: [
          Icon(ok ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: ok ? Colors.green : cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, decoration: ok ? TextDecoration.lineThrough : null)),
        ]);
    return Card(
      color: done ? Colors.green.withValues(alpha: 0.12) : cs.primaryContainer,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          HapticFeedback.selectionClick();
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GrowthGatePage()));
          onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(done ? 'You grew today 🌱' : 'Today’s growth', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                item(learn, 'Learn 1 thing'),
                const SizedBox(height: 4),
                item(news, 'Read 1 important story'),
                const SizedBox(height: 8),
                Text(
                  done
                      ? 'Growth streak ${g.streak} 🔥'
                      : g.enabled
                          ? 'Due by ${h > 12 ? h - 12 : h} ${h >= 12 ? 'PM' : 'AM'} · streak ${g.streak} 🔥'
                          : 'Streak ${g.streak} 🔥',
                  style: tt.bodySmall,
                ),
              ]),
            ),
            if (!done) FilledButton(onPressed: null, style: FilledButton.styleFrom(disabledBackgroundColor: cs.primary, disabledForegroundColor: cs.onPrimary), child: const Text('Start')),
          ]),
        ),
      ),
    );
  }
}
