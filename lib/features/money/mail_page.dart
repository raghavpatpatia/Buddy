import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/cleaner.dart' show fmtBytes;
import '../../core/store.dart';
import '../ui.dart';
import 'mail.dart';
import 'money_ui.dart';
import 'tracking.dart';

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
  bool _loading = false, _sentView = false, _polling = false;

  Future<void> _pollOpens() async {
    setState(() => _polling = true);
    try {
      await MailTracker.poll(notify: false);
    } catch (_) {}
    if (mounted) setState(() => _polling = false);
  }

  List<Widget> _sentList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!MailTracker.ready) {
      return [
        const SizedBox(height: 16),
        const EmptyState(emoji: '👀', title: 'Read tracking isn’t set up yet', subtitle: 'It needs a one-time setup of a tiny tracker on your AWS account (free tier). Once done, emails you send from Buddy show ✓✓ when opened, and you get a notification.'),
      ];
    }
    final sent = MailTracker.sent;
    return [
      if (_polling) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: LinearProgressIndicator()),
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
                  : 'Opened ${t.opens.length > 1 ? '${t.opens.length}× · last ' : ''}${_short(t.opens.last)} ${_time(t.opens.last)}${t.viaGmail ? ' · Gmail' : ''}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Text(_short(t.sentAt), style: tt.labelSmall),
          ),
        ),
      if (sent.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Opens are a strong signal, not proof: some apps block images, Apple Mail may preload them.', textAlign: TextAlign.center, style: tt.labelSmall),
        ),
    ];
  }

  static String _time(DateTime d) => '${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';

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
    final items = _sentView ? const <MailItem>[] : (_items ?? const <MailItem>[]);
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
        onRefresh: () => _sentView ? _pollOpens() : _load(_filter < 0 ? null : _filters[_filter].$2),
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
              for (final (i, f) in _filters.indexed) ...[
                if (i == 0 || MailAccount.isGmail)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(f.$1),
                      selected: _filter == i && !_sentView,
                      onSelected: (_) {
                        setState(() {
                          _filter = i;
                          _sentView = false;
                        });
                        _load();
                      },
                    ),
                  ),
                if (i == 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      avatar: const Icon(Icons.done_all, size: 16),
                      label: const Text('Sent'),
                      selected: _sentView,
                      onSelected: (_) {
                        setState(() {
                          _sentView = true;
                          _sel.clear();
                        });
                        _pollOpens();
                      },
                    ),
                  ),
              ],
            ]),
          ),
          if (_sentView) ..._sentList(context),
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
          if (_loading && !_sentView) const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: LinearProgressIndicator()),
          if (_error != null && !_sentView) EmptyState(emoji: '📡', title: 'Offline?', subtitle: _error!),
          if (!_sentView && !_loading && _error == null && items.isEmpty) const EmptyState(emoji: '✨', title: 'Nothing here', subtitle: 'Inbox zero vibes.'),
          for (final m in items)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              color: _sel.contains(m.uid) ? cs.secondaryContainer : null,
              child: ListTile(
                onLongPress: () {
                  HapticFeedback.selectionClick();
                  setState(() => _sel.contains(m.uid) ? _sel.remove(m.uid) : _sel.add(m.uid));
                },
                onTap: selecting
                    ? () => setState(() => _sel.contains(m.uid) ? _sel.remove(m.uid) : _sel.add(m.uid))
                    : () async {
                        final deleted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ReadPage(item: m)));
                        if (!mounted) return;
                        setState(() {
                          if (deleted == true) {
                            _items?.removeWhere((x) => x.uid == m.uid);
                          } else {
                            // Opened = read: show it as seen without reloading.
                            final i = _items?.indexOf(m) ?? -1;
                            if (i >= 0) _items![i] = MailItem(m.uid, m.from, m.subject, m.at, true);
                          }
                        });
                      },
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

/// Reads one email the way Gmail shows it: images (trackers blocked), tappable links, attachments.
/// Reply opens Compose pre-filled; Delete asks first and moves it to Trash.
class ReadPage extends StatefulWidget {
  final MailItem item;
  const ReadPage({super.key, required this.item});
  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> {
  MailMessage? _mail;
  String? _error;
  WebViewController? _web;
  double _webHeight = 400;
  final _downloading = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await MailService.read(widget.item.uid);
      final web = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted) // only to measure height; email scripts are stripped
        ..setBackgroundColor(Colors.white)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            if (u == null || r.url.startsWith('about:') || r.url.startsWith('data:')) return NavigationDecision.navigate;
            if (u.scheme == 'mailto') {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposePage(to: u.path, subject: u.queryParameters['subject'])));
            } else {
              launchUrl(u, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
          onPageFinished: (_) => _measure(),
        ));
      await web.loadHtmlString(m.html);
      if (mounted) {
        setState(() {
          _mail = m;
          _web = web;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Couldn’t open this email. Check your connection.');
    }
  }

  /// The web view sits inside the page scroll, so size it to its content (re-measured as images load).
  Future<void> _measure() async {
    for (final wait in [0, 400, 1200, 3000]) {
      await Future.delayed(Duration(milliseconds: wait));
      final h = await _web?.runJavaScriptReturningResult('document.documentElement.scrollHeight');
      final v = double.tryParse('$h');
      if (v != null && mounted && (v - _webHeight).abs() > 4) setState(() => _webHeight = v.clamp(80, 30000));
    }
  }

  Future<void> _open(MailAttachment a) async {
    setState(() => _downloading.add(a.name));
    try {
      final bytes = a.bytes();
      if (bytes == null) throw Exception('empty');
      final dir = Directory('/storage/emulated/0/Download/Buddy');
      File f;
      try {
        await dir.create(recursive: true);
        f = File('${dir.path}/${a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
        await f.writeAsBytes(bytes);
      } catch (_) {
        // No all-files access: keep it in the app's own folder instead.
        f = File('${(await getApplicationDocumentsDirectory()).path}/${a.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}');
        await f.writeAsBytes(bytes);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.path.startsWith('/storage') ? 'Saved to Download/Buddy' : 'Saved')));
      }
      await OpenFilex.open(f.path, type: a.mime);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t save this attachment.')));
    } finally {
      if (mounted) setState(() => _downloading.remove(a.name));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Move this email to Trash?'),
        content: Text('${widget.item.from}: ${widget.item.subject}\n\nYou can restore it from Trash for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MailService.trash([widget.item.uid]);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t delete. Nothing was changed.')));
    }
  }

  void _reply() {
    final m = _mail!;
    final subject = m.subject.toLowerCase().startsWith('re:') ? m.subject : 'Re: ${m.subject}';
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposePage(to: m.fromEmail, subject: subject)));
  }

  static IconData _icon(String mime) => mime.startsWith('image/')
      ? Icons.image_outlined
      : mime.contains('pdf')
          ? Icons.picture_as_pdf_outlined
          : mime.contains('sheet') || mime.contains('excel') || mime.contains('csv')
              ? Icons.table_chart_outlined
              : mime.startsWith('video/')
                  ? Icons.movie_outlined
                  : mime.contains('zip')
                      ? Icons.folder_zip_outlined
                      : Icons.insert_drive_file_outlined;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final m = _mail;
    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        actions: [
          IconButton(onPressed: m == null ? null : _delete, icon: const Icon(Icons.delete_outline), tooltip: 'Move to Trash'),
          IconButton(
            onPressed: m == null
                ? null
                : () => Clipboard.setData(ClipboardData(text: m.text)).then((_) {
                      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    }),
            icon: const Icon(Icons.copy_outlined),
            tooltip: 'Copy text',
          ),
        ],
      ),
      floatingActionButton: m == null || m.fromEmail.isEmpty ? null : FloatingActionButton.extended(onPressed: _reply, icon: const Icon(Icons.reply), label: const Text('Reply')),
      body: _error != null
          ? ListView(padding: pagePadding, children: [
              EmptyState(emoji: '📡', title: 'Offline?', subtitle: _error!),
              Center(child: FilledButton.tonal(onPressed: _load, child: const Text('Try again'))),
            ])
          : m == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.only(bottom: 96), children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SelectableText(m.subject, style: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.25)),
                      const SizedBox(height: 14),
                      Row(children: [
                        CircleAvatar(backgroundColor: cs.primaryContainer, child: Text(m.from.isEmpty ? '?' : m.from[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w800))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(m.from, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(m.fromEmail, style: tt.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                        if (m.at != null) Text(_MailPageState._short(m.at!), style: tt.labelSmall),
                      ]),
                      if (m.trackersBlocked > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Row(children: [
                            Icon(Icons.shield_outlined, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text('Blocked ${m.trackersBlocked} tracker${m.trackersBlocked == 1 ? '' : 's'}: the sender can’t see you opened this', style: tt.labelSmall),
                          ]),
                        ),
                      if (m.attachments.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 8, runSpacing: 8, children: [
                          for (final a in m.attachments)
                            ActionChip(
                              avatar: _downloading.contains(a.name) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(_icon(a.mime), size: 18),
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 220),
                                child: Text('${a.name} · ${fmtBytes(a.size)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              onPressed: _downloading.contains(a.name) ? null : () => _open(a),
                            ),
                        ]),
                      ],
                      const SizedBox(height: 12),
                    ]),
                  ),
                  SizedBox(height: _webHeight, child: WebViewWidget(controller: _web!)),
                ]),
    );
  }
}

/// Write an email (optionally drafted by Buddy), add attachments, review, then send (with optional read tracking).
class ComposePage extends StatefulWidget {
  final String? to, subject;
  const ComposePage({super.key, this.to, this.subject});
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  late final _to = TextEditingController(text: widget.to), _subject = TextEditingController(text: widget.subject), _body = TextEditingController();
  bool _drafting = false, _sending = false;
  late bool _track = MailTracker.ready && MailTracker.onByDefault;
  final _files = <(String, Uint8List)>[];
  static const _maxBytes = 24 * 1024 * 1024; // Gmail's limit is 25 MB incl. encoding

  int get _total => _files.fold(0, (a, f) => a + f.$2.length);

  @override
  void dispose() {
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    final picked = await FilePicker.pickFiles();
    for (final f in picked) {
      final bytes = await f.readAsBytes();
      if (_total + bytes.length > _maxBytes) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${f.name} is too big: emails can carry up to 25 MB in total.')));
        continue;
      }
      setState(() => _files.add((f.name, bytes)));
    }
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
      'Recipient: ${_to.text.isEmpty ? 'unknown' : _to.text}\nRequest: $what${_files.isEmpty ? '' : '\nAttached: ${_files.map((f) => f.$1).join(', ')}'}',
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
          if (_files.isNotEmpty) Text('📎 ${_files.map((f) => f.$1).join(', ')} (${fmtBytes(_total)})', style: Theme.of(c).textTheme.bodySmall),
          if (_track) Text('👀 Read tracking on: you’ll be notified when it’s opened', style: Theme.of(c).textTheme.bodySmall),
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
      final id = _track ? MailTracker.newId() : null;
      await MailService.send(to: _to.text, subject: _subject.text, body: _body.text, attachments: _files, pixelUrl: id == null ? null : MailTracker.pixelUrl(id));
      if (id != null) await MailTracker.recordSent(id, _to.text.trim(), _subject.text.trim().isEmpty ? '(no subject)' : _subject.text.trim());
      HapticFeedback.mediumImpact();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_track ? 'Sent ✓ · Buddy will tell you when it’s opened' : 'Sent ✓')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t send. Check your connection.')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final valid = _to.text.contains('@') && (_body.text.trim().isNotEmpty || _files.isNotEmpty);
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('New email'), actions: [
        IconButton(onPressed: _attach, icon: const Icon(Icons.attach_file), tooltip: 'Attach files'),
        TextButton.icon(onPressed: _drafting ? null : _draft, icon: const Text('✨'), label: const Text('Draft')),
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
        if (_files.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final f in _files)
              InputChip(
                avatar: const Icon(Icons.attach_file, size: 16),
                label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text('${f.$1} · ${fmtBytes(f.$2.length)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                onDeleted: () => setState(() => _files.remove(f)),
              ),
          ]),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          secondary: const Icon(Icons.done_all),
          title: const Text('Tell me when it’s opened'),
          subtitle: Text(MailTracker.ready ? 'Adds an invisible image, like Mailsuite' : 'Needs read tracking set up (Mail → Sent)', style: tt.bodySmall),
          value: _track,
          onChanged: MailTracker.ready ? (v) => setState(() => _track = v) : null,
        ),
        TextField(controller: _body, onChanged: (_) => setState(() {}), maxLines: null, minLines: 10, decoration: const InputDecoration(hintText: 'Write your email…', border: InputBorder.none)),
      ]),
    );
  }
}
