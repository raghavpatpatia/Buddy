import 'package:flutter/material.dart';

import '../../grow/data/growth_service.dart' show openLink;
import '../controller/jobs_controller.dart';
import '../model/job.dart';
import '../model/match.dart';
import 'job_widgets.dart';

/// Full view of one job: why it fits, skills to brush up, summary, save and apply.
Future<void> showJobDetail(BuildContext context, JobsController c, Job job, {JobMatch? match}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListenableBuilder(listenable: c, builder: (context, _) => _Detail(c, job, match, scroll)),
      ),
    );

class _Detail extends StatelessWidget {
  final JobsController c;
  final Job job;
  final JobMatch? match;
  final ScrollController scroll;
  const _Detail(this.c, this.job, this.match, this.scroll);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final m = match;
    final saved = c.isSaved(job);
    return Column(children: [
      Expanded(
        child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.title, style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.2)),
                const SizedBox(height: 6),
                Text(job.company, style: tt.titleSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
                if (job.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.place_outlined, size: 15, color: cs.onSurfaceVariant),
                    const SizedBox(width: 3),
                    Expanded(child: Text(job.location, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant))),
                  ]),
                ],
              ]),
            ),
            if (m != null) ...[const SizedBox(width: 12), MatchBadge(m.score, size: 56)],
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: jobTags(context, job)),
          if (m?.opportunity != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                Icon(Icons.trending_up, color: cs.onTertiaryContainer),
                const SizedBox(width: 10),
                Expanded(child: Text(m!.opportunity!, style: TextStyle(color: cs.onTertiaryContainer, fontWeight: FontWeight.w600))),
              ]),
            ),
          ],
          if (m != null && m.reasons.isNotEmpty) ...[
            _heading(context, 'Why it fits'),
            for (final r in m.reasons)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(Icons.check_circle, size: 18, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Expanded(child: Text(r)),
                ]),
              ),
          ],
          if (m != null && m.missing.isNotEmpty) ...[
            _heading(context, 'Skills to brush up'),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in m.missing) JobTag(s, icon: Icons.school_outlined, color: cs.secondary)]),
          ],
          if (job.summary.isNotEmpty) ...[
            _heading(context, 'About the role'),
            Text(job.summary, style: tt.bodyMedium?.copyWith(height: 1.45)),
          ],
          const SizedBox(height: 12),
          Text('Full details and applying happen on ${job.source}.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => c.toggleSave(job),
                icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                label: Text(saved ? 'Saved' : 'Save'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 2,
              child: FilledButton.icon(onPressed: () => openLink(job.url), icon: const Icon(Icons.open_in_new), label: const Text('View & apply')),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _heading(BuildContext context, String t) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
      );
}
