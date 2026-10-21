import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/store.dart';
import 'growth.dart';
import 'learn_page.dart' show openLink;

const units = ['lessons', 'videos', 'chapters', 'modules', 'pages'];
String unitOf(Map c) => (c['unit'] as String?) ?? 'lessons';
String unitOne(Map c) => unitOf(c).substring(0, unitOf(c).length - 1);

/// Pace needed to finish on time: lessons/day, or null without a deadline.
({int perDay, int daysLeft})? coursePace(Map c) {
  final d = DateTime.tryParse(c['deadline'] ?? '');
  if (d == null) return null;
  final left = (c['total'] as int) - (c['done'] as int);
  final now = DateTime.now();
  // Whole calendar days, today included (comparing to "now" would drop a day every evening).
  final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays + 1;
  return (perDay: days <= 0 ? left : (left / days).ceil(), daysLeft: days);
}

/// "Continue learning" section: any course, book or playlist with countable units.
class MyCourses extends StatefulWidget {
  const MyCourses({super.key});
  @override
  State<MyCourses> createState() => _MyCoursesState();
}

class _MyCoursesState extends State<MyCourses> {
  Future<void> _bump(Map<String, dynamic> c, int delta) async {
    final all = Store.courses;
    final x = all.firstWhere((e) => e['id'] == c['id']);
    final done = ((x['done'] as int) + delta).clamp(0, x['total'] as int);
    if (done == x['done']) return;
    x['done'] = done;
    final log = Map<String, dynamic>.from(x['log'] ?? {});
    log[dayKey()] = ((log[dayKey()] as int? ?? 0) + delta).clamp(0, 999);
    x['log'] = log;
    await Store.setCourses(all);
    if (delta > 0) {
      HapticFeedback.mediumImpact();
      await Store.addXp(done == x['total'] ? 100 : 5);
      await growthProgress();
      if (mounted && done == x['total']) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('🎓 You finished ${x['name']}! +100 XP')));
      }
    }
    setState(() {});
  }

  Future<void> _edit([Map<String, dynamic>? c]) async {
    final res = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CourseForm(course: c),
    );
    if (res == null) return;
    final all = Store.courses;
    if (res['_delete'] == true) {
      all.removeWhere((e) => e['id'] == c!['id']);
    } else if (c == null) {
      all.add(res);
    } else {
      all[all.indexWhere((e) => e['id'] == c['id'])] = res;
    }
    await Store.setCourses(all);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final courses = Store.courses..sort((a, b) => _urgency(a).compareTo(_urgency(b)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 0, 6),
        child: Row(children: [
          Text('My courses', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add course')),
        ]),
      ),
      if (courses.isEmpty)
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _edit(),
            child: const Padding(
              padding: EdgeInsets.all(20),
              child: Column(children: [
                Text('🎓', style: TextStyle(fontSize: 34)),
                SizedBox(height: 6),
                Text('Add something you\'re learning', style: TextStyle(fontWeight: FontWeight.w700)),
                SizedBox(height: 2),
                Text('Any online course, book or playlist. Buddy tracks progress and tells you the daily pace to finish before your deadline.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
              ]),
            ),
          ),
        ),
      for (final c in courses) _card(c, tt, cs),
    ]);
  }

  /// Sort: active with nearest deadline first, finished last.
  int _urgency(Map c) {
    if (c['done'] >= c['total']) return 1 << 30;
    return coursePace(c)?.daysLeft ?? (1 << 20);
  }

  Widget _card(Map<String, dynamic> c, TextTheme tt, ColorScheme cs) {
    final total = c['total'] as int, done = c['done'] as int;
    final finished = done >= total;
    final pace = coursePace(c);
    final today = (c['log'] as Map?)?[dayKey()] as int? ?? 0;
    // Only flag "behind" in the evening; at 8 AM "0 of 4 today" isn't a failure yet.
    final behind = pace != null && !finished && today < pace.perDay && (DateTime.now().hour >= 18 || pace.daysLeft <= 0);
    final paceText = finished
        ? '🎓 Completed'
        : pace == null
            ? 'No deadline set'
            : pace.daysLeft <= 0
                ? '⚠️ Deadline passed · ${total - done} ${unitOf(c)} left'
                : '${pace.perDay} ${unitOf(c)}/day to finish in ${pace.daysLeft} day${pace.daysLeft == 1 ? '' : 's'} · today $today/${pace.perDay}';
    return Card(
      color: finished ? Colors.green.withValues(alpha: 0.1) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onLongPress: () => _edit(c),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(8)),
                child: Text((c['platform'] as String?)?.isNotEmpty == true ? c['platform'] : 'Course', style: tt.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const Spacer(),
              Text('${(done * 100 / total).round()}%', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              IconButton(onPressed: () => _edit(c), icon: const Icon(Icons.more_vert), visualDensity: VisualDensity.compact),
            ]),
            Text(c['name'], style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: LinearProgressIndicator(
                value: done / total,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
                color: finished ? Colors.green : null,
              ),
            ),
            const SizedBox(height: 6),
            Text('$done of $total ${unitOf(c)}', style: tt.bodySmall),
            Text(paceText, style: tt.bodySmall?.copyWith(color: behind ? cs.error : null, fontWeight: behind ? FontWeight.w700 : null)),
            if (!finished)
              Row(children: [
                if ((c['url'] ?? '').toString().isNotEmpty)
                  TextButton.icon(onPressed: () => openLink(c['url']), icon: const Icon(Icons.play_circle_outline), label: const Text('Continue')),
                const Spacer(),
                IconButton(onPressed: done > 0 ? () => _bump(c, -1) : null, icon: const Icon(Icons.remove), tooltip: 'Undo'),
                FilledButton.tonalIcon(onPressed: () => _bump(c, 1), icon: const Icon(Icons.check), label: Text('+1 ${unitOne(c)}')),
              ]),
          ]),
        ),
      ),
    );
  }
}

class _CourseForm extends StatefulWidget {
  final Map<String, dynamic>? course;
  const _CourseForm({this.course});
  @override
  State<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends State<_CourseForm> {
  late final c = widget.course;
  late final _name = TextEditingController(text: c?['name'] ?? '');
  late final _total = TextEditingController(text: c == null ? '' : '${c!['total']}');
  late final _done = TextEditingController(text: c == null ? '0' : '${c!['done']}');
  late final _url = TextEditingController(text: c?['url'] ?? '');
  late final _platform = TextEditingController(text: c?['platform'] ?? '');
  late String _unit = c?['unit'] ?? 'lessons';
  late DateTime? _deadline = DateTime.tryParse(c?['deadline'] ?? '');

  bool get _valid => _name.text.trim().isNotEmpty && (int.tryParse(_total.text) ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    InputDecoration dec(String l, [String? hint]) => InputDecoration(labelText: l, hintText: hint, border: const OutlineInputBorder());
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c == null ? 'Add a course' : 'Edit course', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _name, onChanged: (_) => setState(() {}), decoration: dec('Name', 'e.g. Full Stack Web Development')),
          const SizedBox(height: 12),
          TextField(controller: _platform, decoration: dec('Where (optional)', 'Platform, book, channel…')),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final p in ['Tutedude', 'Udemy', 'Coursera', 'YouTube', 'Book'])
              ActionChip(label: Text(p), onPressed: () => setState(() => _platform.text = p)),
          ]),
          const SizedBox(height: 12),
          Text('Track progress in', style: tt.labelLarge),
          const SizedBox(height: 6),
          Wrap(spacing: 6, children: [
            for (final u in units) ChoiceChip(label: Text(u), selected: _unit == u, onSelected: (_) => setState(() => _unit = u)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _total, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: dec('Total $_unit'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: _done, keyboardType: TextInputType.number, decoration: dec('Already done'))),
          ]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _deadline ?? DateTime.now().add(const Duration(days: 30)),
                firstDate: DateTime.now().subtract(const Duration(days: 365)),
                lastDate: DateTime.now().add(const Duration(days: 730)),
                helpText: 'Finish by',
              );
              if (d != null) setState(() => _deadline = d);
            },
            icon: const Icon(Icons.event),
            label: Text(_deadline == null ? 'Set a deadline (optional)' : 'Finish by ${_deadline!.day}/${_deadline!.month}/${_deadline!.year}'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
          const SizedBox(height: 12),
          TextField(controller: _url, keyboardType: TextInputType.url, decoration: dec('Link for "Continue" (optional)', 'https://…')),
          const SizedBox(height: 16),
          Row(children: [
            if (c != null)
              TextButton.icon(
                onPressed: () => Navigator.pop(context, {'_delete': true}),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              ),
            const Spacer(),
            FilledButton(
              onPressed: !_valid
                  ? null
                  : () {
                      final total = int.parse(_total.text);
                      Navigator.pop(context, {
                        'id': c?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
                        'name': _name.text.trim(),
                        'platform': _platform.text.trim(),
                        'unit': _unit,
                        'url': _url.text.trim(),
                        'total': total,
                        'done': (int.tryParse(_done.text) ?? 0).clamp(0, total),
                        'deadline': _deadline?.toIso8601String(),
                        'log': c?['log'] ?? {},
                      });
                    },
              child: const Text('Save'),
            ),
          ]),
        ]),
      ),
    );
  }
}
