import 'package:flutter/material.dart';

import '../../../core/arch/load_state.dart';
import '../../../core/arch/time_sort.dart';
import '../../../shared/ui.dart';
import '../../grow/data/feeds.dart' show timeAgo;
import '../../grow/data/growth_service.dart' show openLink;
import '../controller/jobs_controller.dart';
import '../model/job_profile.dart';
import '../model/match.dart';
import 'job_detail_sheet.dart';
import 'job_profile_sheet.dart';
import 'job_widgets.dart';

/// Money → Jobs: openings from many sites ranked for the user, better opportunities and skill gaps.
class JobsPage extends StatefulWidget {
  final JobsController? controller;
  const JobsPage({super.key, this.controller});
  @override
  State<JobsPage> createState() => _JobsPageState();
}

class _JobsPageState extends State<JobsPage> {
  late final c = widget.controller ?? JobsController();

  @override
  void initState() {
    super.initState();
    c.init();
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _editProfile() async {
    final p = await showJobProfileSheet(context, c.profile, onReset: c.reset);
    if (p != null) await c.saveProfile(p);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: c,
        builder: (context, _) => c.profile.setUp ? _results(context) : _welcome(context),
      );

  Widget _welcome(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = c.profile;
    return ListView(padding: pagePadding, children: [
      HeroCard(
        child: Column(children: [
          const Text('💼', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 8),
          Text('Find your next job', style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Buddy searches remote job boards, Hacker News and game studio careers pages, ranks every opening for your skills, and points out better opportunities.',
            textAlign: TextAlign.center,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(onPressed: _editProfile, icon: const Icon(Icons.person_search), label: const Text('Set up my job profile')),
        ]),
      ),
      const SizedBox(height: 8),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Starts with', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _fact(context, Icons.badge_outlined, p.targetRoles.map((r) => r.label).join(', ')),
          _fact(context, Icons.sports_esports_outlined, p.focus.isEmpty ? 'Any field' : p.focus),
          _fact(context, Icons.place_outlined, p.placeLabel.isEmpty ? 'Anywhere (location unknown)' : 'Near ${p.placeLabel}'),
          const SizedBox(height: 4),
          Text('You can change all of this, and add your current job and skills.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      ),
    ]);
  }

  Widget _fact(BuildContext context, IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );

  Widget _results(BuildContext context) {
    final busy = c.state.isLoading;
    return RefreshIndicator(
      onRefresh: () => c.search(force: true),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
        _profileCard(context),
        _scopeChips(context),
        const SizedBox(height: 4),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: false, icon: Icon(Icons.work_outline, size: 18), label: Text('Matches')),
            ButtonSegment(value: true, icon: const Icon(Icons.bookmark_border, size: 18), label: Text('Saved (${c.saved.length})')),
          ],
          selected: {c.showSaved},
          onSelectionChanged: (s) => c.setShowSaved(s.first),
        ),
        if (busy && c.state.data != null) const Padding(padding: EdgeInsets.only(top: 10), child: LinearProgressIndicator()),
        if (c.showSaved) ..._saved(context) else ..._matches(context),
      ]),
    );
  }

  Widget _profileCard(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = c.profile;
    final now = p.currentTitle.isEmpty ? null : '${p.currentTitle} · ${p.years == 0 ? '< 1 yr' : '${p.years} yr${p.years == 1 ? '' : 's'}'}';
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.55),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _editProfile,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(children: [
            CircleAvatar(radius: 22, backgroundColor: cs.surface.withValues(alpha: 0.7), child: const Text('🎯', style: TextStyle(fontSize: 22))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.targetRoles.map((r) => r.label).join(' · '), maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text([p.focus.isEmpty ? 'Any field' : p.focus, if (p.placeLabel.isNotEmpty) p.placeLabel].join(' · '),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall),
                if (now != null) Text('Now: $now', maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                if (p.skills.isEmpty)
                  Text('Add your skills for better matches', style: tt.bodySmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w700)),
              ]),
            ),
            IconButton(tooltip: 'Edit job profile', onPressed: _editProfile, icon: const Icon(Icons.edit_outlined)),
          ]),
        ),
      ),
    );
  }

  Widget _scopeChips(BuildContext context) {
    const icons = {JobScope.near: Icons.near_me_outlined, JobScope.country: Icons.flag_outlined, JobScope.remote: Icons.public, JobScope.worldwide: Icons.travel_explore};
    return SizedBox(
      height: 52,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(vertical: 6), children: [
        for (final s in JobScope.values)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              avatar: Icon(icons[s], size: 16),
              label: Text(c.profile.scopeLabel(s)),
              selected: c.profile.scope == s,
              onSelected: c.state.isLoading ? null : (_) => c.setScope(s),
            ),
          ),
      ]),
    );
  }

  List<Widget> _saved(BuildContext context) {
    final list = c.saved;
    if (list.isEmpty) {
      return const [EmptyState(emoji: '🔖', title: 'No saved jobs yet', subtitle: 'Tap the bookmark on any job to keep it here.')];
    }
    final scores = {for (final m in c.matches) m.job.id: m};
    return [
      if (list.length > 1)
        Align(
          alignment: Alignment.centerRight,
          child: SortButton(
            value: c.sort == TimeSort.oldest ? TimeSort.oldest : TimeSort.newest,
            labels: const {TimeSort.newest: 'Newest', TimeSort.oldest: 'Oldest'},
            onChanged: c.setSort,
          ),
        )
      else
        const SizedBox(height: 8),
      for (final j in list)
        JobTile(
          job: j,
          score: scores[j.id]?.score,
          saved: true,
          onTap: () => showJobDetail(context, c, j, match: scores[j.id]),
          onSave: () => c.toggleSave(j),
        ),
    ];
  }

  List<Widget> _matches(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final st = c.state;
    if (st.data == null) {
      return switch (st) {
        Failed(:final message) => [
            EmptyState(emoji: '📡', title: 'Couldn\'t search right now', subtitle: message),
            Center(child: FilledButton.tonalIcon(onPressed: () => c.search(force: true), icon: const Icon(Icons.refresh), label: const Text('Try again'))),
          ],
        _ => [
            const SizedBox(height: 48),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Center(child: Text('Searching job sites and studios…', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))),
          ],
      };
    }
    final visible = c.visible;
    final roles = c.profile.targetRoles;
    return [
      if (c.opportunities.isNotEmpty) ...[
        const SectionTitle('Better opportunities'),
        for (final m in c.opportunities) _opportunity(context, m),
      ],
      _insights(context),
      SectionTitle('Search other sites', trailing: Text('opens in browser', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant))),
      SizedBox(
        height: 44,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final p in c.platforms)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ActionChip(avatar: Text(p.emoji), label: Text(p.name), onPressed: () => openLink(p.url)),
            ),
        ]),
      ),
      SectionTitle(
        visible.isEmpty ? 'No matches' : '${visible.length} match${visible.length == 1 ? '' : 'es'}',
        trailing: visible.length > 1 ? SortButton(value: c.sort, labels: JobsController.sortLabels, onChanged: c.setSort) : null,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
        child: Text('Updated ${timeAgo(st.data!.at)} ago · pull down to refresh', style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      ),
      if (roles.length > 1)
        SizedBox(
          height: 48,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(bottom: 6), children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(label: const Text('All roles'), selected: c.roleFilter == null, onSelected: (_) => c.setRoleFilter(null)),
            ),
            for (final r in roles)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(label: Text(r.label), selected: c.roleFilter == r.id, onSelected: (_) => c.setRoleFilter(r.id)),
              ),
          ]),
        ),
      if (visible.isEmpty)
        EmptyState(
          emoji: '🔍',
          title: 'Nothing here yet',
          subtitle: c.profile.scope == JobScope.worldwide
              ? 'Add more roles or skills, or try the job sites above.'
              : 'Try Remote or Anywhere, add more roles, or try the job sites above.',
        ),
      for (final m in visible.take(c.shown))
        JobTile.match(m, saved: c.isSaved(m.job), onTap: () => showJobDetail(context, c, m.job, match: m), onSave: () => c.toggleSave(m.job)),
      if (visible.length > c.shown)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Center(
            child: FilledButton.tonalIcon(
              onPressed: c.showMore,
              icon: const Icon(Icons.expand_more),
              label: Text('Show ${(visible.length - c.shown).clamp(0, JobsController.pageSize)} more'),
            ),
          ),
        ),
      if (c.failedSources.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Couldn\'t reach ${c.failedSources.join(', ')} this time.', textAlign: TextAlign.center, style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
    ];
  }

  Widget _opportunity(BuildContext context, JobMatch m) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showJobDetail(context, c, m.job, match: m),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            MatchBadge(m.score),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.job.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onTertiaryContainer)),
                Text(m.job.company, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.bodySmall?.copyWith(color: cs.onTertiaryContainer)),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.trending_up, size: 15, color: cs.onTertiaryContainer),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(m.opportunity!, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: tt.labelMedium?.copyWith(color: cs.onTertiaryContainer, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _insights(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final gaps = c.gaps;
    if (gaps.isEmpty && c.matches.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (gaps.isNotEmpty) ...[
            Text('Skills employers want', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text('Asked for in your best matches, missing from your profile.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (s, share) in gaps) JobTag('$s · ${(share * 100).round()}%', icon: Icons.school_outlined, color: cs.secondary),
            ]),
            const SizedBox(height: 12),
          ],
          switch (c.advice) {
            Ready(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.adviceOffline ? 'Buddy\'s quick plan' : 'Buddy\'s career plan', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SelectableText(value, style: tt.bodyMedium?.copyWith(height: 1.45)),
                if (c.adviceOffline) ...[
                  const SizedBox(height: 8),
                  Text('Turn on the cloud brain in Buddy → Talk for a deeper, AI-written plan.', style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ]),
            Loading() => const Row(children: [
                SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10),
                Text('Thinking about your next move…'),
              ]),
            Failed(:final message) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(message, style: tt.bodySmall?.copyWith(color: cs.error)),
                TextButton.icon(onPressed: c.askAdvice, icon: const Icon(Icons.refresh), label: const Text('Try again')),
              ]),
            Idle() => SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(onPressed: c.askAdvice, icon: const Icon(Icons.auto_awesome), label: const Text('Ask Buddy for a career plan')),
              ),
          },
        ]),
      ),
    );
  }
}

