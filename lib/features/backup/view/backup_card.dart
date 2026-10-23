import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/ui.dart';
import '../controller/backup_controller.dart';

String _when(DateTime? t) {
  if (t == null) return 'never';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${t.day}/${t.month}/${t.year}';
}

/// Asks for the passphrase that protects saved passwords. [confirm] asks twice (when setting it).
Future<String?> askPassphrase(BuildContext context, {bool confirm = false}) async {
  final a = TextEditingController(), b = TextEditingController();
  String? err;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        icon: const Icon(Icons.lock_outline),
        title: Text(confirm ? 'Protect your passwords' : 'Backup passphrase'),
        // Scrolls as a whole when the keyboard is up; the text wraps to the dialog's width.
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            confirm
                ? 'Your mail and AWS passwords are encrypted with this before upload. Nobody, not even Google, can read them without it. If you forget it, those passwords can\'t be restored.'
                : 'Enter the passphrase you chose, to restore your saved passwords.',
            softWrap: true,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(controller: a, obscureText: true, autofocus: true, decoration: const InputDecoration(labelText: 'Passphrase')),
          if (confirm) TextField(controller: b, obscureText: true, decoration: const InputDecoration(labelText: 'Again')),
          if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: SystemColors.danger))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (a.text.length < 8) return set(() => err = 'Use at least 8 characters.');
              if (confirm && a.text != b.text) return set(() => err = 'They don\'t match.');
              Navigator.pop(context, true);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ),
  );
  return ok == true ? a.text : null;
}

/// Restores from the cloud, asking for the passphrase when the backup has passwords. Returns true when done.
Future<bool> runRestore(BuildContext context) async {
  final c = BackupController.instance;
  String? pass;
  if (c.cloud?.hasSecrets == true) {
    pass = await askPassphrase(context);
    if (pass == null) return false;
  }
  return c.restore(passphrase: pass);
}

/// Settings card: sign in, automatic backup status, back up now, restore, passphrase.
class BackupCard extends StatelessWidget {
  const BackupCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = BackupController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tt = Theme.of(context).textTheme;
        if (!c.signedIn) {
          return AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Keep your data safe in the cloud', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Sign in with Google and Buddy backs everything up automatically to your own Firebase project, so a reinstall or a new phone loses nothing.',
                  style: tt.bodySmall),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: c.busy ? null : c.signIn,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Sign in with Google'),
              ),
              if (c.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.error!, style: const TextStyle(color: SystemColors.danger))),
            ]),
          );
        }
        if (c.needsChoice) {
          return AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('You have a backup from ${_when(c.cloud?.at)}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Automatic backup is paused so this phone can\'t overwrite it. Restore it, or replace it with what\'s on this phone.', style: tt.bodySmall),
              const SizedBox(height: 10),
              Wrap(spacing: 8, children: [
                FilledButton.icon(
                  onPressed: c.busy
                      ? null
                      : () async {
                          if (await runRestore(context)) await SystemNavigator.pop();
                        },
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore (Buddy restarts)'),
                ),
                OutlinedButton(
                  onPressed: c.busy
                      ? null
                      : () async {
                          final sure = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Replace the cloud backup?'),
                              content: Text('The backup from ${_when(c.cloud?.at)} is overwritten with this phone\'s data. This can\'t be undone.'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replace')),
                              ],
                            ),
                          );
                          if (sure == true) await c.backupNow();
                        },
                  child: const Text('Replace with this phone'),
                ),
              ]),
              if (c.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.error!, style: const TextStyle(color: SystemColors.danger))),
            ]),
          );
        }
        return AppCard(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.cloud_done_outlined, color: SystemColors.mana),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Backed up ${_when(c.cloud?.at ?? c.lastBackup)}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('${c.email} · automatic', style: tt.bodySmall),
                ]),
              ),
              if (c.busy) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ]),
            const SizedBox(height: 6),
            Text(
              c.hasPassphrase ? 'Saved passwords are included, encrypted with your passphrase.' : 'Saved passwords are not backed up yet. Set a passphrase to include them.',
              style: tt.bodySmall,
            ),
            if (c.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(c.error!, style: const TextStyle(color: SystemColors.danger))),
            Wrap(spacing: 4, children: [
              TextButton.icon(onPressed: c.busy ? null : c.backupNow, icon: const Icon(Icons.backup_outlined, size: 18), label: const Text('Back up now')),
              TextButton.icon(
                onPressed: c.busy
                    ? null
                    : () async {
                        final p = await askPassphrase(context, confirm: true);
                        if (p != null) await c.setPassphrase(p);
                      },
                icon: const Icon(Icons.lock_outline, size: 18),
                label: Text(c.hasPassphrase ? 'Change passphrase' : 'Set passphrase'),
              ),
              TextButton.icon(
                onPressed: c.busy || c.cloud == null
                    ? null
                    : () async {
                        final sure = await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Restore from backup?'),
                            content: Text('Replaces what is on this phone with the backup from ${_when(c.cloud?.at)}. Buddy closes afterwards; open it again.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                              FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Restore')),
                            ],
                          ),
                        );
                        if (sure == true && context.mounted && await runRestore(context)) await SystemNavigator.pop();
                      },
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Restore'),
              ),
              TextButton(onPressed: c.busy ? null : c.signOut, child: const Text('Sign out')),
            ]),
          ]),
        );
      },
    );
  }
}

/// First-run card: "Used Buddy before?" — sign in and bring everything back before setting up.
class RestoreOnSetupCard extends StatefulWidget {
  const RestoreOnSetupCard({super.key});
  @override
  State<RestoreOnSetupCard> createState() => _RestoreOnSetupCardState();
}

class _RestoreOnSetupCardState extends State<RestoreOnSetupCard> {
  bool _restored = false;

  @override
  Widget build(BuildContext context) {
    final c = BackupController.instance;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final tt = Theme.of(context).textTheme;
        final String text;
        final Widget? action;
        if (_restored) {
          text = 'Your data is back. Finish the steps below and Buddy picks up where you left off.';
          action = null;
        } else if (!c.signedIn) {
          text = 'Used Buddy before? Sign in to bring back your data from the cloud.';
          action = FilledButton.tonalIcon(onPressed: c.busy ? null : c.signIn, icon: const Icon(Icons.cloud_download_outlined), label: const Text('Sign in with Google'));
        } else if (c.cloud == null) {
          text = 'Signed in as ${c.email}. No backup yet, so Buddy will start backing up once you\'re set up.';
          action = null;
        } else {
          text = 'Found a backup from ${_when(c.cloud!.at)} (${c.email}).';
          action = FilledButton.icon(
            onPressed: c.busy
                ? null
                : () async {
                    if (await runRestore(context)) setState(() => _restored = true);
                  },
            icon: const Icon(Icons.restore),
            label: const Text('Restore my data'),
          );
        }
        return AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_restored ? Icons.check_circle : Icons.cloud_outlined, color: _restored ? Colors.green : SystemColors.mana),
              const SizedBox(width: 10),
              Expanded(child: Text(text, style: tt.bodyMedium)),
              if (c.busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            if (action != null) ...[const SizedBox(height: 10), action],
            if (c.error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(c.error!, style: const TextStyle(color: SystemColors.danger))),
          ]),
        );
      },
    );
  }
}
