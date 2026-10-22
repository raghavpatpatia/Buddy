import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/mail_controller.dart';
import '../data/mail_service.dart';
import '../data/read_tracker.dart';
import '../model/mail.dart';
import 'compose_page.dart';
import 'widgets.dart';
import 'connect_sheet.dart';
import 'reader_page.dart';

export 'compose_page.dart' show ComposePage;
export 'connect_sheet.dart' show showMailConnect;

/// Short date for lists: time today, otherwise "21 Oct".
String shortDate(DateTime d) {
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  return '${d.day} ${monthShort[d.month - 1]}';
}

String _time(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';

/// Money → Mail: inbox, clean-up filters, sent-with-tracking list and bulk trash (always confirmed).
class MailPage extends StatefulWidget {
  final MailController? controller;
  const MailPage({super.key, this.controller});
  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  late final c = widget.controller ?? MailController();

  @override
  void initState() {
    super.initState();
    if (MailAccount.linked) c.refresh();
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    await showMailConnect(context);
    if (!mounted) return;
    setState(() {});
    if (MailAccount.linked) c.refresh();
  }

  Future<void> _trash() async {
    final picked = c.list.where((m) => c.selected.contains(m.uid)).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('Move ${picked.length} email${picked.length == 1 ? '' : 's'} to Trash?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in picked.take(5)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${m.from}: ${m.subject}', maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (picked.length > 5) Text('…and ${picked.length - 5} more'),
          const SizedBox(height: 8),
          Text('You can restore them from Trash for 30 days.', style: Theme.of(d).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.trashSelected();
      HapticFeedback.mediumImpact();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved ${picked.length} to Trash')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t delete. Nothing was changed.')));
    }
  }

  Future<void> _search() async {
    final ctl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Search mail'),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: MailAccount.isGmail ? 'from:swiggy older_than:60d' : 'Sender or subject')),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Search'))],
      ),
    );
    ctl.dispose();
    if (q != null && q.isNotEmpty) c.show(SearchMode(q));
  }

  Future<void> _open(MailItem m) async {
    final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReadPage(item: m)));
    deleted == true ? c.removeItem(m.uid) : c.markSeen(m);
  }

  @override
  Widget build(BuildContext context) {
    if (!MailAccount.linked) return _NotLinked(onLink: _link);
    return ListenableBuilder(listenable: c, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final mode = c.mode;
    final items = mode is SentMode ? const <MailItem>[] : c.list;
    final selecting = c.selecting;

    return Scaffold(
      floatingActionButton: selecting
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ComposePage())),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Compose'),
            ),
      bottomNavigationBar: !selecting
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(children: [
                  TextButton(onPressed: c.clearSelection, child: const Text('Cancel')),
                  const Spacer(),
                  TextButton(onPressed: c.selectAll, child: const Text('All')),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _trash, icon: const Icon(Icons.delete_outline), label: Text('Trash ${c.selected.length}')),
                ]),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: c.refresh,
        child: ListView(padding: pagePadding.copyWith(bottom: 96), children: [
          Row(children: [
            CircleAvatar(radius: 16, backgroundColor: cs.primaryContainer, child: Text(MailAccount.address![0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: Text(MailAccount.address!, style: tt.titleSmall, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: _search, icon: const Icon(Icons.search), tooltip: 'Search'),
            IconButton(onPressed: () => showMailConnect(context).then((_) => setState(() {})), icon: const Icon(Icons.manage_accounts_outlined), tooltip: 'Account'),
          ]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (i, f) in InboxMode.filters.indexed) ...[
                if (i == 0 || MailAccount.isGmail)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(f.$1), selected: mode is InboxMode && mode.filter == i, onSelected: (_) => c.show(InboxMode(i))),
                  ),
                if (i == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(avatar: const Icon(Icons.done_all, size: 16), label: const Text('Sent'), selected: mode is SentMode, onSelected: (_) => c.show(const SentMode())),
                  ),
              ],
            ]),
          ),
          if (mode case InboxMode(:final filter) when filter > 0 && items.isNotEmpty && !selecting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBanner(
                icon: Icons.cleaning_services_outlined,
                text: '${items.length} old ${InboxMode.filters[filter].$1.split(' ').first.toLowerCase()} emails found.',
                action: 'Select all',
                onTap: c.selectAll,
              ),
            ),
          if (mode is SentMode)
            ..._sentList(context)
          else ...[
            if (c.items.isLoading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
            if (c.items case Failed(:final message)) EmptyState(emoji: '📡', title: 'Offline?', subtitle: message),
            if (c.items is Ready && items.isEmpty)
              mode is SearchMode
                  ? const EmptyState(emoji: '🔍', title: 'No emails match', subtitle: 'Try other words, or check the spelling.')
                  : const EmptyState(emoji: '✨', title: 'Nothing here', subtitle: 'Inbox zero vibes.'),
            if (items.isNotEmpty && !selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                child: Text(c.unread == 0 ? 'All read' : '${c.unread} unread', style: tt.labelLarge?.copyWith(color: c.unread == 0 ? cs.onSurfaceVariant : cs.primary)),
              ),
            for (final m in items)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 2),
                color: c.selected.contains(m.uid) ? cs.secondaryContainer : null,
                child: ListTile(
                  onLongPress: () {
                    HapticFeedback.selectionClick();
                    c.toggle(m.uid);
                  },
                  onTap: selecting ? () => c.toggle(m.uid) : () => _open(m),
                  leading: selecting
                      ? Checkbox(value: c.selected.contains(m.uid), onChanged: (_) => c.toggle(m.uid))
                      : MailAvatar(from: m.from, seen: m.seen),
                  title: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: m.seen ? FontWeight.w500 : FontWeight.w800)),
                  subtitle: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: m.seen ? null : TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                  trailing: Text(m.at == null ? '' : shortDate(m.at!), style: m.seen ? tt.labelSmall : tt.labelSmall?.copyWith(color: cs.primary, fontWeight: FontWeight.w800)),
                ),
              ),
            if (items.isNotEmpty && !selecting) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Long-press to select emails.', textAlign: TextAlign.center, style: tt.bodySmall)),
          ],
        ]),
      ),
    );
  }

  List<Widget> _sentList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!ReadTracker.ready) {
      return const [
        SizedBox(height: 16),
        EmptyState(
          emoji: '👀',
          title: 'Read tracking isn’t set up yet',
          subtitle: 'It needs a one-time setup of a tiny tracker on your AWS account (free tier). Once done, emails you send from Buddy show ✓✓ when opened, and you get a notification.',
        ),
      ];
    }
    final sent = c.tracker.sent;
    return [
      if (c.polling) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
      if (sent.isEmpty) const EmptyState(emoji: '📤', title: 'No tracked emails yet', subtitle: 'Send an email from Buddy with “Tell me when it’s opened” on.'),
      for (final t in sent)
        Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            leading: Icon(t.opens.isEmpty ? Icons.done : Icons.done_all, color: t.opens.isEmpty ? cs.outline : cs.primary),
            title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              t.opens.isEmpty
                  ? 'To ${t.to} · not opened yet'
                  : 'Opened ${t.opens.length > 1 ? '${t.opens.length}× · last ' : ''}${shortDate(t.opens.last)} ${_time(t.opens.last)}${t.viaGmail ? ' · Gmail' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(shortDate(t.sentAt), style: tt.labelSmall),
          ),
        ),
      if (sent.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Opens are a strong signal, not proof: some apps block images, Apple Mail may preload them.', textAlign: TextAlign.center, style: tt.labelSmall),
        ),
    ];
  }
}

class _NotLinked extends StatelessWidget {
  final VoidCallback onLink;
  const _NotLinked({required this.onLink});
  @override
  Widget build(BuildContext context) => ListView(padding: pagePadding, children: [
        const SizedBox(height: 24),
        const EmptyState(emoji: '📬', title: 'Your inbox, with Buddy', subtitle: 'Clean up old promotions in bulk, write emails with Buddy’s help, and pick up bank alerts for Spend.'),
        const SizedBox(height: 8),
        FilledButton.icon(onPressed: onLink, icon: const Icon(Icons.link), label: const Text('Link email account'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
        const SizedBox(height: 8),
        Text('Nothing is ever sent or deleted without your confirmation.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
