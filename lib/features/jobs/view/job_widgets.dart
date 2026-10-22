import 'package:flutter/material.dart';

import '../../grow/data/feeds.dart' show timeAgo;
import '../model/job.dart';
import '../model/match.dart';

/// Round match score; green for strong, primary for fair, grey for weak.
class MatchBadge extends StatelessWidget {
  final int score;
  final double size;
  const MatchBadge(this.score, {super.key, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = score >= 70 ? Colors.green.shade600 : (score >= 45 ? cs.primary : cs.outline);
    return Semantics(
      label: '$score percent match',
      child: SizedBox.square(
        dimension: size,
        child: Stack(alignment: Alignment.center, children: [
          SizedBox.expand(
            child: CircularProgressIndicator(value: score / 100, strokeWidth: 4, color: color, backgroundColor: color.withValues(alpha: 0.15)),
          ),
          Text('$score', style: TextStyle(fontWeight: FontWeight.w800, fontSize: size * 0.3, color: color)),
        ]),
      ),
    );
  }
}

/// Small rounded label used for remote, pay, age and source.
class JobTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const JobTag(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: (color ?? cs.surfaceContainerHighest).withValues(alpha: color == null ? 1 : 0.12), borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: fg), const SizedBox(width: 3)],
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: fg, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

/// Tags shown under a job: remote, pay, age and, with [source], where it came from.
List<Widget> jobTags(BuildContext context, Job j, {bool source = true}) => [
      if (j.remote) JobTag('Remote', icon: Icons.public, color: Colors.teal.shade600),
      if (j.salary != null) JobTag(j.salary!, icon: Icons.payments_outlined, color: Colors.green.shade700),
      if (j.posted != null) JobTag('${timeAgo(j.posted)} ago', icon: Icons.schedule),
      if (source) JobTag(j.source),
    ];

/// One job in a list: score, title, company and place, tags and a save star.
class JobTile extends StatelessWidget {
  final Job job;
  final int? score;
  final bool saved;
  final VoidCallback onTap, onSave;
  const JobTile({super.key, required this.job, this.score, required this.saved, required this.onTap, required this.onSave});

  factory JobTile.match(JobMatch m, {required bool saved, required VoidCallback onTap, required VoidCallback onSave}) =>
      JobTile(job: m.job, score: m.score, saved: saved, onTap: onTap, onSave: onSave);

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final where = [job.company, if (job.location.isNotEmpty) job.location].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (score != null) ...[MatchBadge(score!), const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
                const SizedBox(height: 3),
                Text(where, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: jobTags(context, job, source: false)),
              ]),
            ),
            IconButton(
              tooltip: saved ? 'Remove from saved' : 'Save job',
              onPressed: onSave,
              icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border, color: saved ? cs.primary : cs.onSurfaceVariant),
            ),
          ]),
        ),
      ),
    );
  }
}
