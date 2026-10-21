import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/format.dart' show fmtBytes;
import '../../../shared/ui.dart';
import '../controller/mail_controller.dart';
import '../data/mail_service.dart';
import '../data/read_tracker.dart';

/// Write an email (optionally drafted by Buddy) with attachments, review it, then send.
class ComposePage extends StatefulWidget {
  final String? to, subject;
  const ComposePage({super.key, this.to, this.subject});
  @override
  State<ComposePage> createState() => _ComposePageState();
}

class _ComposePageState extends State<ComposePage> {
  final c = ComposeController();
  late final _to = TextEditingController(text: widget.to), _subject = TextEditingController(text: widget.subject), _body = TextEditingController();
  bool _sent = false;

  bool get _dirty => !_sent && (_body.text.trim().isNotEmpty || c.files.isNotEmpty || (_subject.text.trim().isNotEmpty && _subject.text != (widget.subject ?? '')));

  /// Asks before throwing away a half-written email.
  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Discard this email?'),
        content: const Text('What you wrote and any attachments will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Keep writing')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Discard')),
        ],
      ),
    );
    if (leave == true && mounted) {
      _sent = true;
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    c.dispose();
    _to.dispose();
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _attach() async {
    for (final f in await FilePicker.pickFiles()) {
      if (!c.attach(f.name, await f.readAsBytes()) && mounted) _toast('${f.name} is too big: emails can carry up to 25 MB in total.');
    }
  }

  Future<void> _draft() async {
    final ctl = TextEditingController();
    final what = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('✨ What should it say?'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(hintText: 'e.g. Ask my manager for leave on Friday, polite and short'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, ctl.text.trim()), child: const Text('Draft')),
        ],
      ),
    );
    ctl.dispose();
    if (what == null || what.isEmpty) return;
    final r = await c.draft(what, _to.text);
    if (!mounted) return;
    if (r == null) return _toast('Drafting needs the cloud brain (Talk → brain icon).');
    if (r.$1 != null) _subject.text = r.$1!;
    _body.text = r.$2;
    setState(() {});
  }

  Future<void> _review() async {
    final bad = ComposeController.badRecipients(_to.text);
    if (bad.isNotEmpty) return _toast('Check ${bad.length == 1 ? 'this address' : 'these addresses'}: ${bad.join(', ')}');
    final tt = Theme.of(context).textTheme;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (s) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send this email?', style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text('From: ${MailAccount.address}\nTo: ${_to.text}\nSubject: ${_subject.text}', style: tt.bodySmall),
            if (c.files.isNotEmpty) Text('📎 ${c.files.map((f) => f.$1).join(', ')} (${fmtBytes(c.totalBytes)})', style: tt.bodySmall),
            if (c.track) Text('👀 Read tracking on: you’ll be notified when it’s opened', style: tt.bodySmall),
            const Divider(height: 20),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: SingleChildScrollView(child: Text(_body.text)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(s, true),
              icon: const Icon(Icons.send),
              label: const Text('Send now'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            TextButton(onPressed: () => Navigator.pop(s, false), child: const Text('Keep editing')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await c.send(to: _to.text, subject: _subject.text, body: _body.text);
      HapticFeedback.mediumImpact();
      if (mounted) {
        final tracked = c.track;
        _sent = true;
        Navigator.pop(context);
        _toast(tracked ? 'Sent ✓ · Buddy will tell you when it’s opened' : 'Sent ✓');
      }
    } catch (_) {
      if (mounted) _toast('Couldn’t send. Check your connection.');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final valid = _to.text.contains('@') && (_body.text.trim().isNotEmpty || c.files.isNotEmpty);
    final tt = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('New email'),
          actions: [
            IconButton(onPressed: _attach, icon: const Icon(Icons.attach_file), tooltip: 'Attach files'),
            TextButton.icon(onPressed: c.drafting ? null : _draft, icon: const Text('✨'), label: const Text('Draft')),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: valid && !c.sending ? _review : null,
              icon: c.sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.visibility_outlined),
              label: const Text('Review & send'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
          ),
        ),
        body: ListView(
          padding: pagePadding,
          children: [
            if (c.drafting) const LinearProgressIndicator(),
            TextField(
              controller: _to,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'To', hintText: 'name@example.com'),
            ),
            TextField(
              controller: _subject,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Subject'),
            ),
            if (c.files.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in c.files)
                    InputChip(
                      avatar: const Icon(Icons.attach_file, size: 16),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Text('${f.$1} · ${fmtBytes(f.$2.length)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      onDeleted: () => c.detach(f),
                    ),
                ],
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              secondary: const Icon(Icons.done_all),
              title: const Text('Tell me when it’s opened'),
              subtitle: Text(ReadTracker.ready ? 'Adds an invisible image, like Mailsuite' : 'Needs read tracking set up (Mail → Sent)', style: tt.bodySmall),
              value: c.track,
              onChanged: ReadTracker.ready ? c.setTrack : null,
            ),
            TextField(
              controller: _body,
              onChanged: (_) => setState(() {}),
              maxLines: null,
              minLines: 10,
              decoration: const InputDecoration(hintText: 'Write your email…', border: InputBorder.none),
            ),
          ],
        ),
      ),
    );
  }
}
