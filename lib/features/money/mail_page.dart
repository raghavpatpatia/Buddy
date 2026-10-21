import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/store.dart';
import '../ui.dart';
import 'mail.dart';
import 'money_ui.dart';

/// Link (or change) the email account: address + app password, verified before saving.
Future<void> showMailConnect(BuildContext context) => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _ConnectSheet());

class _ConnectSheet extends StatefulWidget {
  const _ConnectSheet();
  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends State<_ConnectSheet> {
  final _addr = TextEditingController(text: MailAccount.address ?? '');
  final _pass = TextEditingController();
  bool _busy = false, _scan = MailAccount.scanBankEmails;
  String? _error;

  @override
  void dispose() {
    _addr.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _link() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await MailAccount.link(_addr.text, _pass.text);
      await Store.raw.setBool('mail_scan_bank', _scan);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Linked ${MailAccount.address} ✓')));
      }
    } catch (e) {
      setState(() => _error = 'Couldn’t sign in. Check the address and app password (not your normal password).');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(MailAccount.linked ? 'Email account' : 'Link your email', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Gmail uses an App password: a separate 16-letter key you can revoke anytime. Your real password is never used.', style: tt.bodySmall),
          const SizedBox(height: 12),
          AppCard(
            color: cs.surfaceContainerHigh,
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('1. Turn on 2-Step Verification in your Google account', style: tt.bodySmall),
              Text('2. Open App passwords → name it “Buddy” → Create', style: tt.bodySmall),
              Text('3. Copy the 16 letters and paste them below', style: tt.bodySmall),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse('https://myaccount.google.com/apppasswords'), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Open App passwords'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(controller: _addr, keyboardType: TextInputType.emailAddress, autocorrect: false, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.alternate_email))),
          const SizedBox(height: 10),
          TextField(
            controller: _pass,
            onChanged: (_) => setState(() {}),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: 'App password', prefixIcon: const Icon(Icons.key), helperText: MailAccount.linked ? 'Leave empty to keep the saved one' : null),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Find bank alerts in my email'),
            subtitle: const Text('Only amount, debit/credit, date & bank are kept'),
            value: _scan,
            onChanged: (v) {
              setState(() => _scan = v);
              if (MailAccount.linked) Store.raw.setBool('mail_scan_bank', v);
            },
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_error!, style: TextStyle(color: cs.error))),
          FilledButton(
            onPressed: _busy || _addr.text.trim().isEmpty || (_pass.text.trim().isEmpty && !MailAccount.linked) ? null : (_pass.text.trim().isEmpty ? () => Navigator.pop(context) : _link),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(MailAccount.linked ? 'Save' : 'Verify & link'),
          ),
          if (MailAccount.linked)
            TextButton(
              onPressed: () async {
                await MailAccount.unlink();
                if (context.mounted) Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: cs.error),
              child: const Text('Unlink this account'),
            ),
        ]),
      ),
    );
  }
}

/// Money → Mail: inbox on the phone, bulk clean-up to Trash, and compose. Nothing is sent or deleted without a confirm.
class MailPage extends StatefulWidget {
  const MailPage({super.key});
  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  static const _filters = [
    ('Inbox', ''),
    ('Promotions 30d+', 'category:promotions older_than:30d'),
    ('Social 30d+', 'category:social older_than:30d'),
    ('Unread 90d+', 'is:unread older_than:90d'),
  ];
  var _filter = 0;
  List<MailItem>? _items;
  String? _error;
  final _sel = <int>{};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (MailAccount.linked) _load();
  }

  Future<void> _load([String? query]) async {
    setState(() {
      _loading = true;
      _error = null;
      _sel.clear();
    });
    try {
      final q = query ?? _filters[_filter].$2;
      final r = q.isEmpty ? await MailService.inbox() : await MailService.search(q);
      if (mounted) setState(() => _items = r);
    } catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t reach your mailbox. Pull to retry.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _trash() async {
    final picked = _items!.where((m) => _sel.contains(m.uid)).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text('Move ${picked.length} email${picked.length == 1 ? '' : 's'} to Trash?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final m in picked.take(5)) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• ${m.from}: ${m.subject}', maxLines: 1, overflow: TextOverflow.ellipsis)),
          if (picked.length > 5) Text('…and ${picked.length - 5} more'),
          const SizedBox(height: 8),
          Text('You can restore them from Trash for 30 days.', style: Theme.of(c).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _loading = true);
    try {
      await MailService.trash(picked.map((m) => m.uid).toList());
      HapticFeedback.mediumImpact();
      if (mounted) {
        setState(() {
          _items!.removeWhere((m) => _sel.contains(m.uid));
          _sel.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Moved ${picked.length} to Trash')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t delete. Nothing was changed.')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _searchDialog() async {
    final ctl = TextEditingController();
    final q = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Search mail'),
        content: TextField(controller: ctl, autofocus: true, decoration: InputDecoration(hintText: MailAccount.isGmail ? 'from:swiggy older_than:60d' : 'Sender or subject')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Search'))],
      ),
    );
    ctl.dispose();
    if (q != null && q.isNotEmpty) {
      setState(() => _filter = -1);
      _load(q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!MailAccount.linked) {
      return ListView(padding: pagePadding, children: [
        const SizedBox(height: 24),
        const EmptyState(emoji: '📬', title: 'Your inbox, with Buddy', subtitle: 'Clean up old promotions in bulk, write emails with Buddy’s help, and pick up bank alerts for Spend.'),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () async {
            await showMailConnect(context);
            if (!mounted) return;
            setState(() {});
            if (MailAccount.linked) _load();
          },
          icon: const Icon(Icons.link),
          label: const Text('Link email account'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 8),
        Text('Nothing is ever sent or deleted without your confirmation.', textAlign: TextAlign.center, style: tt.bodySmall),
      ]);
    }
    final items = _items ?? const <MailItem>[];
    final selecting = _sel.isNotEmpty;
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
                  TextButton(onPressed: () => setState(_sel.clear), child: const Text('Cancel')),
                  const Spacer(),
                  TextButton(onPressed: () => setState(() => _sel.addAll(items.map((m) => m.uid))), child: const Text('All')),
                  const SizedBox(width: 8),
                  FilledButton.icon(onPressed: _trash, icon: const Icon(Icons.delete_outline), label: Text('Trash ${_sel.length}')),
                ]),
              ),
            ),
      body: RefreshIndicator(
        onRefresh: () => _load(_filter < 0 ? null : _filters[_filter].$2),
        child: ListView(padding: pagePadding.copyWith(bottom: 96), children: [
          Row(children: [
            CircleAvatar(radius: 16, backgroundColor: cs.primaryContainer, child: Text(MailAccount.address![0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
            const SizedBox(width: 10),
            Expanded(child: Text(MailAccount.address!, style: tt.titleSmall, overflow: TextOverflow.ellipsis)),
            IconButton(onPressed: _searchDialog, icon: const Icon(Icons.search), tooltip: 'Search'),
            IconButton(onPressed: () => showMailConnect(context).then((_) => setState(() {})), icon: const Icon(Icons.manage_accounts_outlined), tooltip: 'Account'),
          ]),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final (i, f) in _filters.indexed)
                if (i == 0 || MailAccount.isGmail)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.$1),
                      selected: _filter == i,
                      onSelected: (_) {
                        setState(() => _filter = i);
                        _load();
                      },
                    ),
                  ),
            ]),
          ),
          if (_filter > 0 && items.isNotEmpty && !selecting)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBanner(
                icon: Icons.cleaning_services_outlined,
                text: '${items.length} old ${_filters[_filter].$1.split(' ').first.toLowerCase()} emails found.',
                action: 'Select all',
                onTap: () => setState(() => _sel.addAll(items.map((m) => m.uid))),
              ),
            ),
          if (_loading) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
          if (_error != null) EmptyState(emoji: '📡', title: 'Offline?', subtitle: _error!),
          if (!_loading && _error == null && items.isEmpty) const EmptyState(emoji: '✨', title: 'Nothing here', subtitle: 'Inbox zero vibes.'),
          for (final m in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              color: _sel.contains(m.uid) ? cs.secondaryContainer : null,
              child: ListTile(
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sel.contains(m.uid) ? _sel.remove(m.uid) : _sel.add(m.uid));
                },
                onTap: selecting ? () => setState(() => _sel.contains(m.uid) ? _sel.remove(m.uid) : _sel.add(m.uid)) : null,
                leading: selecting
                    ? Checkbox(value: _sel.contains(m.uid), onChanged: (v) => setState(() => v == true ? _sel.add(m.uid) : _sel.remove(m.uid)))
                    : CircleAvatar(backgroundColor: cs.surfaceContainerHighest, child: Text(m.from.isEmpty ? '?' : m.from[0].toUpperCase())),
                title: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: m.seen ? FontWeight.w500 : FontWeight.w800)),
                subtitle: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Text(m.at == null ? '' : _short(m.at!), style: tt.labelSmall),
              ),
            ),
          if (items.isNotEmpty && !selecting) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Long-press to select emails.', textAlign: TextAlign.center, style: tt.bodySmall)),
        ]),
      ),
    );
  }

  static String _short(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
  }
}

/// Write an email (optionally drafted by Buddy), review it, then send.
class ComposePage extends StatefulWidget {
  const ComposePage({super.key});
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final _to = TextEditingController(), _subject = TextEditingController(), _body = TextEditingController();
  bool _drafting = false, _sending = false;

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _draft() async {
    final ctl = TextEditingController();
    final what = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('✨ What should it say?'),
        content: TextField(controller: ctl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'e.g. Ask my manager for leave on Friday, polite and short')),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(c, ctl.text.trim()), child: const Text('Draft'))],
      ),
    );
    ctl.dispose();
    if (what == null || what.isEmpty) return;
    setState(() => _drafting = true);
    final name = Store.profile['name'] as String? ?? '';
    final r = await askBuddy(
      'You write clear, warm, professional emails. Output exactly: first line "Subject: …", a blank line, then the body signed "$name". No markdown.',
      'Recipient: ${_to.text.isEmpty ? 'unknown' : _to.text}\nRequest: $what',
      maxTokens: 700,
    );
    if (!mounted) return;
    setState(() => _drafting = false);
    if (r == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Drafting needs the cloud brain (Talk → brain icon).')));
      return;
    }
    final lines = r.split('\n');
    if (lines.first.toLowerCase().startsWith('subject:')) {
      _subject.text = lines.first.substring(8).trim();
      _body.text = lines.skip(1).join('\n').trim();
    } else {
      _body.text = r;
    }
  }

  Future<void> _review() async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Send this email?', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text('From: ${MailAccount.address}\nTo: ${_to.text}\nSubject: ${_subject.text}', style: Theme.of(c).textTheme.bodySmall),
          const Divider(height: 20),
          ConstrainedBox(constraints: const BoxConstraints(maxHeight: 280), child: SingleChildScrollView(child: Text(_body.text))),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.send), label: const Text('Send now'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52))),
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep editing')),
        ]),
      ),
    );
    if (ok != true) return;
    setState(() => _sending = true);
    try {
      await MailService.send(to: _to.text, subject: _subject.text, body: _body.text);
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent ✓')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t send. Check your connection.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _to.text.contains('@') && _body.text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('New email'), actions: [
        TextButton.icon(onPressed: _drafting ? null : _draft, icon: const Text('✨'), label: const Text('Draft with Buddy')),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: valid && !_sending ? _review : null,
            icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.visibility_outlined),
            label: const Text('Review & send'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          ),
        ),
      ),
      body: ListView(padding: pagePadding, children: [
        if (_drafting) const LinearProgressIndicator(),
        TextField(controller: _to, keyboardType: TextInputType.emailAddress, autocorrect: false, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'To', hintText: 'name@example.com')),
        TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject')),
        const SizedBox(height: 8),
        TextField(controller: _body, onChanged: (_) => setState(() {}), maxLines: null, minLines: 10, decoration: const InputDecoration(hintText: 'Write your email…', border: InputBorder.none)),
      ]),
    );
  }
}
