import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' show openAppSettings;

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/spend_controller.dart';
import '../data/mail_service.dart';
import '../model/txn.dart';
import 'mail_page.dart' show showMailConnect;
import 'widgets.dart';

/// Money → Spend: month totals, budget pace, last 7 days, categories and every debit/credit.
class SpendPage extends StatefulWidget {
  final SpendController? controller;
  const SpendPage({super.key, this.controller});
  @override
  State<SpendPage> createState() => _SpendPageState();
}

class _SpendPageState extends State<SpendPage> {
  late final c = widget.controller ?? SpendController();

  @override
  void initState() {
    super.initState();
    if (c.hasSources) _sync(quiet: true);
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _toast(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _sync({bool quiet = false}) async {
    try {
      final n = await c.syncNow();
      if (n == null) return;
      if (!quiet && mounted) _toast(n == 0 ? 'All caught up ✓' : '$n new transaction${n == 1 ? '' : 's'} added');
    } catch (e) {
      if (!quiet && mounted) _toast('Couldn’t sync: $e');
    }
  }

  Future<void> _enableSms() async {
    if (await c.enableSms() || !mounted) return;
    if (await c.smsBlocked() && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('SMS access is turned off for Buddy. Allow it in Settings → Permissions.'),
        action: SnackBarAction(label: 'Open', onPressed: openAppSettings),
      ));
    } else if (mounted) {
      _toast('Buddy needs SMS access to read bank alerts.');
    }
  }

  Future<void> _editBudget() async {
    final ctl = TextEditingController(text: c.budget > 0 ? c.budget.round().toString() : '');
    final v = await showDialog<double>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: '₹ ', hintText: 'e.g. 30000', helperText: 'Buddy shows how much you can safely spend per day.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, double.tryParse(ctl.text) ?? 0), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) await c.setBudget(v);
  }

  Future<void> _addCash() async {
    final amt = TextEditingController();
    var debit = true, tried = false;
    String? cat;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(s).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add cash entry', style: Theme.of(s).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [ButtonSegment(value: true, label: Text('Spent'), icon: Icon(Icons.arrow_upward)), ButtonSegment(value: false, label: Text('Received'), icon: Icon(Icons.arrow_downward))],
              selected: {debit},
              onSelectionChanged: (v) => set(() => debit = v.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amt,
              autofocus: true,
              onChanged: (_) => set(() {}),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0',
                border: InputBorder.none,
                errorText: tried && parseAmount(amt.text) == null ? 'Enter an amount between ₹1 and ₹10 crore' : null,
              ),
            ),
            if (debit) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (name, e) in categories) ChoiceChip(label: Text('$e $name'), selected: cat == name, onSelected: (on) => set(() => cat = on ? name : null)),
              ]),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => parseAmount(amt.text) != null ? Navigator.pop(s, true) : set(() => tried = true),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              child: const Text('Add'),
            ),
          ]),
        ),
      ),
    );
    final v = parseAmount(amt.text);
    amt.dispose();
    if (ok == true && v != null) {
      HapticFeedback.lightImpact();
      await c.addCash(v, debit: debit, category: debit ? cat : null);
    }
  }

  Future<void> _openTxn(Txn original) async {
    var t = original;
    await showModalBottomSheet(
      context: context,
      builder: (s) => StatefulBuilder(
        builder: (s, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_signed(t), style: Theme.of(s).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: t.debit ? null : gainColor(s, 1))),
            Text('${t.bank} · ${_src(t.source)} · ${_when(t.at)}', style: Theme.of(s).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(s).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (name, e) in categories)
                ChoiceChip(
                  label: Text('$e $name'),
                  selected: t.category == name,
                  onSelected: (on) {
                    HapticFeedback.selectionClick();
                    c.setCategory(t, on ? name : null);
                    set(() => t = on ? t.copyWith(category: name) : t.copyWith(clearCategory: true));
                  },
                ),
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Exclude from totals'),
              subtitle: const Text('For transfers between your own accounts'),
              value: t.hidden,
              onChanged: (v) {
                c.setHidden(t, v);
                set(() => t = t.copyWith(hidden: v));
              },
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(s);
                c.remove(t);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove this entry'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(s).colorScheme.error),
            ),
          ]),
        ),
      ),
    );
  }

  static String _signed(Txn t) => inr(t.debit ? -t.amount : t.amount, sign: true, decimals: t.amount % 1 == 0 ? 0 : 2);
  static String _src(String s) => switch (s) { 'sms' => 'SMS', 'email' => 'Email', _ => 'Cash' };
  static String _when(DateTime d) => '${d.day} ${monthShort[d.month - 1]}, ${d.hour % 12 == 0 ? 12 : d.hour % 12}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';

  static String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(d).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : '${weekdayShort(d)}, ${d.day} ${monthShort[d.month - 1]}';
  }

  static String _ago(DateTime d) {
    final m = DateTime.now().difference(d).inMinutes;
    return m < 1 ? 'just now' : m < 60 ? '$m min ago' : m < 1440 ? '${m ~/ 60} h ago' : '${m ~/ 1440} d ago';
  }

  static Color _catColor(ColorScheme cs, int i) => [cs.primary, cs.tertiary, cs.secondary, Colors.orange, Colors.pinkAccent, cs.outline][i % 6];

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = c.summary;
    final noSources = !c.hasSources;
    final insight = c.insight;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _addCash, icon: const Icon(Icons.add), label: const Text('Cash')),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(padding: pagePadding.copyWith(bottom: 96), children: [
          if (noSources) _SetupCard(onSms: _enableSms, onEmail: () => showMailConnect(context).then((_) => _sync())),
          if (!noSources && !c.sms.enabled) InfoBanner(icon: Icons.sms_outlined, text: 'Add bank SMS for complete tracking.', action: 'Allow', onTap: _enableSms),
          _MonthHero(c: c, s: s, onBudget: _editBudget),
          if (c.isThisMonth && c.hasAny) ...[
            BuddyTakeCard(
              text: switch (insight) { Ready(:final value) => value, Failed(:final message) => message, _ => c.ruleInsight() },
              loading: insight.isLoading,
              onAsk: c.askInsight,
              askLabel: 'Deeper insight',
              answered: insight is Ready,
              footnote: insight is Ready ? 'Only totals were shared, never messages or banks.' : '',
            ),
            const SectionTitle('Last 7 days'),
            AppCard(
              child: WeekBars(
                data: [for (final (d, v) in c.last7()) (weekdayShort(d), v.round())],
                goal: c.budget > 0 ? (c.budget / c.daysInMonth).round() : 0,
                color: cs.primary,
                overIsBad: c.budget > 0,
                emptyText: 'No spending in the last week.',
              ),
            ),
          ],
          if (s.byCategory.isNotEmpty) ...[
            const SectionTitle('Where it went'),
            AppCard(
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(children: [
                    for (final (i, e) in s.byCategory.take(6).indexed) Expanded(flex: (e.value / s.spent * 1000).round().clamp(1, 1000), child: Container(height: 12, color: _catColor(cs, i))),
                  ]),
                ),
                const SizedBox(height: 12),
                for (final (i, e) in s.byCategory.take(6).indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(cs, i), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(e.key == 'Uncategorised' ? '❔' : categoryEmoji(e.key)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.key)),
                      Text('${(e.value / s.spent * 100).round()}%', style: tt.bodySmall),
                      const SizedBox(width: 12),
                      SizedBox(width: 84, child: Text(inr(e.value), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
                    ]),
                  ),
                if (s.byCategory.any((e) => e.key == 'Uncategorised')) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tip: tap a transaction to give it a category.', style: tt.bodySmall)),
              ]),
            ),
          ],
          SectionTitle(
            'Transactions',
            trailing: c.sync.isLoading
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : (noSources ? null : TextButton.icon(onPressed: _sync, icon: const Icon(Icons.sync, size: 18), label: const Text('Sync'))),
          ),
          if (s.txns.isEmpty)
            EmptyState(
              emoji: '🧾',
              title: noSources ? 'Nothing tracked yet' : 'No transactions this month',
              subtitle: noSources ? 'Allow bank SMS or link your email above, or add a cash entry.' : 'Pull down to sync again.',
            ),
          for (final e in s.byDay.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(children: [
                Text(_dayLabel(e.key), style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text(inr(-MonthSummary.daySpent(e.value)), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Column(children: [for (final t in e.value) _TxnTile(t, onTap: () => _openTxn(t))]),
            ),
          ],
          if (c.lastSync != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Synced ${_ago(c.lastSync!)} · ${[if (c.sms.enabled) 'SMS', if (MailAccount.linked) 'Email'].join(' + ')} · only amounts are read 🔒',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ]),
      ),
    );
  }
}

class _MonthHero extends StatelessWidget {
  final SpendController c;
  final MonthSummary s;
  final VoidCallback onBudget;
  const _MonthHero({required this.c, required this.s, required this.onBudget});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final budget = c.budget;
    final now = DateTime.now();
    final onPace = budget * (c.isThisMonth ? now.day / c.daysInMonth : 1);
    return Card(
      color: cs.primaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
        child: Column(children: [
          Row(children: [
            IconButton(onPressed: () => c.shiftMonth(-1), icon: const Icon(Icons.chevron_left)),
            Expanded(child: Text('${monthLong[c.month.month - 1]} ${c.month.year}', textAlign: TextAlign.center, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(onPressed: c.isThisMonth ? null : () => c.shiftMonth(1), icon: const Icon(Icons.chevron_right)),
          ]),
          Text('Spent', style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
          FittedBox(child: Text(inr(s.spent), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()]))),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
            StatChip(icon: Icons.south_west, label: 'In ${inr(s.received)}'),
            StatChip(icon: Icons.balance, label: 'Net ${inr(s.received - s.spent, sign: true)}'),
          ]),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: budget <= 0
                ? OutlinedButton.icon(onPressed: onBudget, icon: const Icon(Icons.flag_outlined), label: const Text('Set a monthly budget'))
                : InkWell(
                    onTap: onBudget,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Column(children: [
                        LinearProgressIndicator(
                          value: (s.spent / budget).clamp(0, 1),
                          minHeight: 10,
                          borderRadius: BorderRadius.circular(8),
                          color: s.spent > budget ? cs.error : s.spent > onPace ? Colors.orange : cs.primary,
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: Text('${inr(s.spent)} of ${inr(budget)}', style: tt.bodySmall)),
                          Text(
                            s.spent >= budget
                                ? 'Over by ${inr(s.spent - budget)}'
                                : c.isThisMonth
                                    ? '${inr((budget - s.spent) / c.daysLeft)}/day for ${c.daysLeft} days'
                                    : '${inr(budget - s.spent)} saved',
                            style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ]),
                      ]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Txn t;
  final VoidCallback onTap;
  const _TxnTile(this.t, {required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: t.debit ? cs.surfaceContainerHighest : gainColor(context, 1).withValues(alpha: 0.15),
        child: t.category != null
            ? Text(categoryEmoji(t.category), style: const TextStyle(fontSize: 18))
            : Icon(t.debit ? Icons.north_east : Icons.south_west, size: 18, color: t.debit ? cs.onSurfaceVariant : gainColor(context, 1)),
      ),
      title: Text(t.category ?? (t.debit ? 'Paid' : 'Received'), style: TextStyle(fontWeight: FontWeight.w600, decoration: t.hidden ? TextDecoration.lineThrough : null)),
      subtitle: Text('${t.bank} · ${_SpendPageState._src(t.source)}'),
      trailing: Text(
        _SpendPageState._signed(t),
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: t.hidden ? cs.outline : (t.debit ? cs.onSurface : gainColor(context, 1)), fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// First-run card: explains exactly what is read, then one tap per source.
class _SetupCard extends StatelessWidget {
  final VoidCallback onSms, onEmail;
  const _SetupCard({required this.onSms, required this.onEmail});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Track spending automatically', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.lock_outline, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text('Buddy reads only the amount, debit/credit, date and bank. Message text, merchants and account numbers are never saved. SMS from people are never read.', style: tt.bodySmall),
            ),
          ]),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: onSms, icon: const Icon(Icons.sms_outlined), label: const Text('Allow bank SMS'), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48))),
          const SizedBox(height: 8),
          OutlinedButton.icon(onPressed: onEmail, icon: const Icon(Icons.alternate_email), label: const Text('Link email for bank alerts'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48))),
        ]),
      ),
    );
  }
}
