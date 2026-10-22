import 'package:flutter/material.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/news_controller.dart';
import '../data/feeds.dart';
import '../model/news.dart';
import 'growth_page.dart' show readAndReflect;

/// Grow → News: pick a feed, read a story, write a takeaway.
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  final c = NewsController();

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

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final items = c.state is Failed ? const <NewsItem>[] : c.items;
    final error = switch (c.state) { Failed(:final message) => message, _ => null };
    return Column(children: [
      SizedBox(
        height: 56,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          children: [
            for (final f in feeds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(label: Text('${f.emoji} ${f.name}'), selected: f.id == c.feed.id, onSelected: (_) => c.select(f)),
              ),
          ],
        ),
      ),
      if (items != null && items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
          child: Row(children: [
            Text('${items.length} headlines', style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            const Spacer(),
            SortButton(value: c.sort, labels: NewsController.sortLabels, onChanged: c.setSort),
          ]),
        ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => c.load(force: true),
          child: items == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: items.isEmpty ? 1 : items.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  itemBuilder: (_, i) {
                    if (items.isEmpty) {
                      return EmptyState(emoji: '📡', title: 'No headlines', subtitle: error ?? 'Pull down to refresh.');
                    }
                    final n = items[i];
                    return InkWell(
                      onTap: () => readAndReflect(context, n),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(n.title, style: tt.titleMedium?.copyWith(fontWeight: i == 0 ? FontWeight.w800 : FontWeight.w600, height: 1.3)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Flexible(
                              child: Text(n.source, maxLines: 1, overflow: TextOverflow.ellipsis, style: tt.labelMedium?.copyWith(color: cs.primary)),
                            ),
                            if (n.at != null) Text('  ·  ${timeAgo(n.at)} ago', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
        ),
      ),
    ]);
  }
}
