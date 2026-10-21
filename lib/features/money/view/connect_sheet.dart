import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui.dart';
import '../data/mail_service.dart';

/// Opens the sheet to link or change the email account (address + app password, verified first).
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
      await MailAccount.setScanBankEmails(_scan);
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
              if (MailAccount.linked) MailAccount.setScanBankEmails(v);
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
