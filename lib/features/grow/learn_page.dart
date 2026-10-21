import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'courses.dart';
import 'feeds.dart';
import 'growth.dart';
import 'math_card.dart';
import 'lessons.dart';

Future<void> openLink(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);

class LearnPage extends StatefulWidget {
  const LearnPage({super.key});
  @override
  State<LearnPage> createState() => _LearnPageState();
}

class _LearnPageState extends State<LearnPage> {
  Map<String, dynamic>? _wiki;
  bool _wikiLoading = true;

  @override
  void initState() {
    super.initState();
    Feeds.wikiToday().then((w) => mounted ? setState(() {
          _wiki = w;
          _wikiLoading = false;
        }) : null);
  }

  Future<void> _open(Subject s) async {
    await openLessonSheet(context, s);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final learned = Store.learnedToday;
    return RefreshIndicator(
      onRefresh: () async {
        final w = await Feeds.wikiToday();
        setState(() => _wiki = w);
      },
      child: ListView(padding: pagePadding, children: [
        const MyCourses(),
        const SizedBox(height: 4),
        const MathCard(),
        const SizedBox(height: 8),
        HeroCard(
          child: Column(children: [
            Text(learned.isEmpty ? 'Pick any lesson' : '${learned.length} learned today 🎉', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            Text('${subjects.length} subjects · 2 min each · 1 a day keeps your growth streak', textAlign: TextAlign.center, style: tt.bodyMedium),
            const SizedBox(height: 10),
            LinearProgressIndicator(value: learned.length / subjects.length, minHeight: 10, borderRadius: BorderRadius.circular(8)),
            const SizedBox(height: 8),
            Text('${Store.lessonsTotal} lesson${Store.lessonsTotal == 1 ? '' : 's'} learned all-time · +10 XP each', style: tt.bodySmall),
          ]),
        ),
        const SectionTitle("Today's lessons"),
        // Rows of two tiles that grow with their text (a fixed-ratio grid clipped titles on 360 dp phones).
        for (var i = 0; i < subjects.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _subjectTile(subjects[i], learned.contains(subjects[i].id))),
                const SizedBox(width: 10),
                Expanded(
                  child: i + 1 < subjects.length ? _subjectTile(subjects[i + 1], learned.contains(subjects[i + 1].id)) : const SizedBox(),
                ),
              ]),
            ),
          ),
        const SectionTitle('Wikipedia today'),
        if (_wikiLoading)
          const AppCard(child: Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())))
        else if (_wiki == null)
          const AppCard(child: EmptyState(emoji: '📡', title: 'Offline', subtitle: 'Connect to the internet for today\'s featured article and facts.'))
        else ...[
          if (_wiki!['tfa'] != null) _featured(_wiki!['tfa']),
          if ((_wiki!['dyk'] as List).isNotEmpty)
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('💡 Did you know…', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                for (final t in _wiki!['dyk'])
                  Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('• …$t', style: tt.bodyMedium)),
              ]),
            ),
          if ((_wiki!['onthisday'] as List).isNotEmpty)
            AppCard(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('📅 On this day', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                for (final o in _wiki!['onthisday'])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Text('${o['year']}', style: const TextStyle(fontWeight: FontWeight.w800)),
                    title: Text(o['text'], style: tt.bodyMedium),
                    onTap: o['url'] == null ? null : () => openLink(o['url']),
                  ),
              ]),
            ),
        ],
      ]),
    );
  }

  Widget _subjectTile(Subject s, bool done) {
    final c = Color(s.color);
    final lesson = s.lessons[todaysIndex(s)];
    return Material(
      color: c.withValues(alpha: done ? 0.10 : 0.18),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _open(s),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(s.emoji, style: const TextStyle(fontSize: 28)),
              const Spacer(),
              if (done) const Icon(Icons.check_circle, color: Colors.green),
            ]),
            const SizedBox(height: 12),
            Text(s.name, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(lesson.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
        ),
      ),
    );
  }

  Widget _featured(Map t) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: t['url'] == null ? null : () => openLink(t['url']),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (t['thumb'] != null)
              Image.network(t['thumb'], height: 160, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('⭐ Featured article', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Text(t['title'] ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(t['extract'] ?? '', maxLines: 5, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
}

/// Opens a subject's lesson + quiz. Used by the Learn grid and the daily growth check.
Future<void> openLessonSheet(BuildContext context, Subject s) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _LessonSheet(subject: s),
    );

class _LessonSheet extends StatefulWidget {
  final Subject subject;
  const _LessonSheet({required this.subject});
  @override
  State<_LessonSheet> createState() => _LessonSheetState();
}

class _LessonSheetState extends State<_LessonSheet> {
  int _skip = 0;
  int? _picked;

  Lesson get _l => widget.subject.lessons[todaysIndex(widget.subject, _skip)];

  /// Option order shuffled per lesson (stable seed from the title) so the answer isn't always in the same slot.
  List<int> get _order {
    var seed = 0;
    for (final c in _l.title.codeUnits) {
      seed = (seed * 31 + c) & 0x7fffffff;
    }
    return List.generate(_l.options.length, (i) => i)..shuffle(Random(seed));
  }

  Future<void> _answer(int i) async {
    if (_picked != null) return;
    setState(() => _picked = i);
    final correct = i == _l.answer;
    HapticFeedback.mediumImpact();
    if (correct && !Store.learnedToday.contains(widget.subject.id)) {
      await Store.markLearned(widget.subject.id);
      await Store.bumpLessons();
      await Store.addXp(10);
      await growthProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Color(widget.subject.color);
    final tt = Theme.of(context).textTheme;
    final l = _l;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Row(children: [
          Text(widget.subject.emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 8),
          Text(widget.subject.name, style: TextStyle(color: c, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (_skip > 0) Text('Bonus lesson', style: tt.labelSmall),
        ]),
        const SizedBox(height: 10),
        Text(l.title, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        Text(l.body, style: tt.bodyLarge?.copyWith(height: 1.5)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => openLink(l.link), icon: const Icon(Icons.open_in_new, size: 18), label: const Text('Go deeper')),
        ),
        const Divider(height: 24),
        Text('Quick check ✏️', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(l.question, style: tt.bodyLarge),
        const SizedBox(height: 10),
        for (final i in _order)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton(
              onPressed: () => _answer(i),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                alignment: Alignment.centerLeft,
                backgroundColor: _picked == null
                    ? null
                    : i == l.answer
                        ? Colors.green.withValues(alpha: 0.18)
                        : i == _picked
                            ? Colors.red.withValues(alpha: 0.15)
                            : null,
                side: BorderSide(
                  color: _picked != null && i == l.answer ? Colors.green : Theme.of(context).colorScheme.outlineVariant,
                  width: _picked != null && i == l.answer ? 2 : 1,
                ),
              ),
              child: Row(children: [
                Expanded(child: Text(l.options[i])),
                if (_picked != null && i == l.answer) const Icon(Icons.check, color: Colors.green),
                if (_picked == i && i != l.answer) const Icon(Icons.close, color: Colors.red),
              ]),
            ),
          ),
        if (_picked != null) ...[
          const SizedBox(height: 6),
          Text(
            _picked == l.answer ? '🎉 Correct! +10 XP' : 'Not quite. The right answer is highlighted. Try a bonus lesson!',
            style: tt.titleSmall?.copyWith(color: _picked == l.answer ? Colors.green : null, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => setState(() {
              _skip++;
              _picked = null;
            }),
            icon: const Icon(Icons.auto_stories),
            label: const Text('Another lesson'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ]),
    );
  }
}
