import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/arch/load_state.dart';
import '../../../core/format.dart' show fmtBytes;
import '../../../shared/ui.dart';
import '../controller/mail_controller.dart';
import '../model/mail.dart';
import 'compose_page.dart';
import 'mail_page.dart' show shortDate;

/// Reads one email like Gmail: images (trackers blocked), tappable links, attachments, reply and trash.
class ReadPage extends StatefulWidget {
  final MailItem item;
  const ReadPage({super.key, required this.item});
  @override
  State<ReadPage> createState() => _ReadPageState();
}

class _ReadPageState extends State<ReadPage> {
  late final c = ReaderController(widget.item);
  WebViewController? _web;
  double _webHeight = 400;

  @override
  void initState() {
    super.initState();
    c.addListener(_onState);
    c.load();
  }

  @override
  void dispose() {
    c.removeListener(_onState);
    c.dispose();
    super.dispose();
  }

  void _onState() {
    if (c.state case Ready(:final value) when _web == null) _buildWeb(value);
  }

  void _buildWeb(MailMessage m) {
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted) // only to measure height; email scripts are stripped
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: _onLink, onPageFinished: (_) => _measure()))
      ..loadHtmlString(m.html);
  }

  NavigationDecision _onLink(NavigationRequest r) {
    final u = Uri.tryParse(r.url);
    if (u == null || r.url.startsWith('about:') || r.url.startsWith('data:')) return NavigationDecision.navigate;
    if (u.scheme == 'mailto') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposePage(to: u.path, subject: u.queryParameters['subject'])));
    } else {
      launchUrl(u, mode: LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  /// Sizes the web view to its content, re-measuring while images load.
  Future<void> _measure() async {
    for (final wait in [0, 400, 1200, 3000]) {
      await Future.delayed(Duration(milliseconds: wait));
      if (!mounted) return;
      final v = double.tryParse('${await _web?.runJavaScriptReturningResult('document.documentElement.scrollHeight')}');
      if (v != null && mounted && (v - _webHeight).abs() > 4) setState(() => _webHeight = v.clamp(80, 30000));
    }
  }

  Future<void> _openAttachment(MailAttachment a) async {
    try {
      final f = await c.save(a);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(f.path.startsWith('/storage') ? 'Saved to Download/Buddy' : 'Saved')));
      final r = await OpenFilex.open(f.path, type: a.mime);
      if (r.type != ResultType.done && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved, but no app on this phone opens ${a.name.contains('.') ? '.${a.name.split('.').last}' : 'this'} files.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t save this attachment.')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: const Text('Move this email to Trash?'),
        content: Text('${widget.item.from}: ${widget.item.subject}\n\nYou can restore it from Trash for 30 days.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Move to Trash')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await c.trash();
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Couldn’t delete. Nothing was changed.')));
    }
  }

  void _reply(MailMessage m) {
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
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final m = c.state.data;
    return Scaffold(
      appBar: AppBar(title: const SizedBox.shrink(), actions: [
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
      ]),
      floatingActionButton: m == null || m.fromEmail.isEmpty ? null : FloatingActionButton.extended(onPressed: () => _reply(m), icon: const Icon(Icons.reply), label: const Text('Reply')),
      body: switch (c.state) {
        Failed(:final message) => ListView(padding: pagePadding, children: [
            EmptyState(emoji: '📡', title: 'Offline?', subtitle: message),
            Center(child: FilledButton.tonal(onPressed: c.load, child: const Text('Try again'))),
          ]),
        Ready(:final value) when _web != null => _Body(m: value, web: _web!, webHeight: _webHeight, downloading: c.downloading, onAttachment: _openAttachment, icon: _icon),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  final MailMessage m;
  final WebViewController web;
  final double webHeight;
  final Set<String> downloading;
  final void Function(MailAttachment) onAttachment;
  final IconData Function(String) icon;
  const _Body({required this.m, required this.web, required this.webHeight, required this.downloading, required this.onAttachment, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
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
            if (m.at != null) Text(shortDate(m.at!), style: tt.labelSmall),
          ]),
          if (m.trackersBlocked > 0)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(children: [
                Icon(Icons.shield_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(child: Text('Blocked ${m.trackersBlocked} tracker${m.trackersBlocked == 1 ? '' : 's'}: the sender can’t see you opened this', style: tt.labelSmall)),
              ]),
            ),
          if (m.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final a in m.attachments)
                ActionChip(
                  avatar: downloading.contains(a.name) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon(a.mime), size: 18),
                  label: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 220), child: Text('${a.name} · ${fmtBytes(a.size)}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                  onPressed: downloading.contains(a.name) ? null : () => onAttachment(a),
                ),
            ]),
          ],
          const SizedBox(height: 12),
        ]),
      ),
      SizedBox(height: webHeight, child: WebViewWidget(controller: web)),
    ]);
  }
}
