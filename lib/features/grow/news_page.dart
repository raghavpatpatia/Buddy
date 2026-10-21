import 'package:flutter/material.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'feeds.dart';
import 'growth.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  late Feed _feed = feeds.firstWhere((f) => f.id == Store.raw.getString('news_feed'), orElse: () => feeds.first);
  List<NewsItem>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() => _error = null);
    try {
      final items = await Feeds.load(_feed, force: force);
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) {
        setState(() {
          _items = [];
          _error = 'Couldn\'t load ${_feed.name}. Check your internet and pull to refresh.';
        });
      }
    }
  }

  void _select(Feed f) {
    Store.raw.setString('news_feed', f.id);
    setState(() {
      _feed = f;
      _items = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
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
                child: ChoiceChip(label: Text('${f.emoji} ${f.name}'), selected: f.id == _feed.id, onSelected: (_) => _select(f)),
              ),
          ],
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _load(force: true),
          child: _items == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _items!.isEmpty ? 1 : _items!.length,
                  separatorBuilder: (_, _) => Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
                  itemBuilder: (_, i) {
                    if (_items!.isEmpty) {
                      return EmptyState(emoji: '📡', title: 'No headlines', subtitle: _error ?? 'Pull down to refresh.');
                    }
                    final n = _items![i];
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
