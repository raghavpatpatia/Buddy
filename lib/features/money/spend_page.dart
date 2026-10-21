import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui.dart';
import 'ledger.dart';
import 'mail.dart';
import 'mail_page.dart' show showMailConnect;
import 'money_ui.dart';

/// Money → Spend: monthly picture, budget pace, weekly bars and every debit/credit (amount only).
class SpendPage extends StatefulWidget {
  const SpendPage({super.key});
  @override
  State<SpendPage> createState() => _SpendPageState();
}

class _SpendPageState extends State<SpendPage> {
  var _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _syncing = false;
  String? _ai;
  bool _aiLoading = false;

  @override
  void initState() {
    super.initState();
    Ledger.changed.addListener(_refresh);
    if (Ledger.smsOn || MailAccount.linked) _sync(quiet: true);
  }

  @override
  void dispose() {
    Ledger.changed.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => mounted ? setState(() {}) : null;

  Future<void> _sync({bool quiet = false}) async {
    setState(() => _syncing = true);
    try {
      final n = await Ledger.sync();
      if (!quiet && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(n == 0 ? 'All caught up ✓' : '$n new transaction${n == 1 ? '' : 's'} added')));
    } catch (e) {
      if (!quiet && mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Couldn’t sync: $e')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _enableSms() async {
    if (await Ledger.enableSms()) {
      await _sync();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SMS permission denied. You can allow it in App info → Permissions.')));
    }
    if (mounted) setState(() {});
  }

  Future<void> _askAi() async {
    setState(() => _aiLoading = true);
    final r = await askBuddy(
      'You are Buddy, a friendly, practical money coach for a young professional in India. Use only the numbers given. '
          'Reply in 3 short bullet points: one observation, one specific saving tip, one encouragement. Plain text, use ₹. No markdown headers.',
      Ledger.summaryForAi(),
      maxTokens: 500,
    );
    if (mounted) {
      setState(() {
        _aiLoading = false;
        _ai = r ?? 'Turn on the cloud brain (Talk → brain icon) for personalised insights. Meanwhile: ${_ruleInsight()}';
      });
    }
  }

  String _ruleInsight() {
    final w = Ledger.last7();
    final week = w.fold(0.0, (a, e) => a + e.$2);
    final top = w.reduce((a, b) => a.$2 >= b.$2 ? a : b);
    if (week == 0) return 'No spending in the last 7 days. 🎉';
    return 'You spent ${inr(week)} in the last 7 days; the biggest day was ${weekdayShort(top.$1)} (${inr(top.$2)}).';
  }

  Future<void> _editBudget() async {
    final ctl = TextEditingController(text: Ledger.monthlyBudget > 0 ? Ledger.monthlyBudget.round().toString() : '');
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Monthly budget'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(prefixText: '₹ ', hintText: 'e.g. 30000', helperText: 'Buddy shows how much you can safely spend per day.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctl.text) ?? 0), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null) await Ledger.setBudget(v);
  }

  Future<void> _addCash() async {
    final amt = TextEditingController();
    var debit = true;
    String? cat;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(c).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Add cash entry', style: Theme.of(c).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              decoration: const InputDecoration(prefixText: '₹ ', hintText: '0', border: InputBorder.none),
            ),
            if (debit) ...[
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final (name, e) in categories) ChoiceChip(label: Text('$e $name'), selected: cat == name, onSelected: (s) => set(() => cat = s ? name : null)),
              ]),
            ],
            const SizedBox(height: 16),
            FilledButton(onPressed: () => Navigator.pop(c, true), style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Add')),
          ]),
        ),
      ),
    );
    final v = double.tryParse(amt.text.trim());
    amt.dispose();
    if (ok == true && v != null && v > 0) {
      HapticFeedback.lightImpact();
      await Ledger.addCash(v, debit, debit ? cat : null);
    }
  }

  Future<void> _openTxn(Txn t) async {
    await showModalBottomSheet(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(inr(t.debit ? -t.amount : t.amount, sign: true, decimals: t.amount % 1 == 0 ? 0 : 2),
                style: Theme.of(c).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: t.debit ? null : gainColor(c, 1))),
            Text('${t.bank} · ${_src(t.source)} · ${_when(t.at)}', style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(c).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (name, e) in categories)
                ChoiceChip(
                  label: Text('$e $name'),
                  selected: t.category == name,
                  onSelected: (s) {
                    HapticFeedback.selectionClick();
                    set(() => t.category = s ? name : null);
                    Ledger.update(t);
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
                set(() => t.hidden = v);
                Ledger.update(t);
              },
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(c);
                Ledger.remove(t);
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove this entry'),
              style: TextButton.styleFrom(foregroundColor: Theme.of(c).colorScheme.error),
            ),
          ]),
        ),
      ),
    );
  }

  static String _src(String s) => switch (s) { 'sms' => 'SMS', 'email' => 'Email', _ => 'Cash' };
  static String _when(DateTime d) => '${d.day} ${_mon[d.month - 1]}, ${TimeOfDay.fromDateTime(d).hourOfPeriod == 0 ? 12 : TimeOfDay.fromDateTime(d).hourOfPeriod}:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  static const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    return diff == 0 ? 'Today' : diff == 1 ? 'Yesterday' : '${weekdayShort(d)}, ${d.day} ${_mon[d.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final isThisMonth = _month.year == now.year && _month.month == now.month;
    final txns = Ledger.all.where((t) => t.at.year == _month.year && t.at.month == _month.month).toList();
    final counted = txns.where((t) => !t.hidden);
    final spent = Ledger.spent(counted), received = Ledger.received(counted);
    final budget = Ledger.monthlyBudget;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final daysLeft = isThisMonth ? daysInMonth - now.day + 1 : 0;
    final noSources = !Ledger.smsOn && !MailAccount.linked;

    // Group by day
    final groups = <DateTime, List<Txn>>{};
    for (final t in txns) {
      groups.putIfAbsent(DateTime(t.at.year, t.at.month, t.at.day), () => []).add(t);
    }

    final byCat = <String, double>{};
    for (final t in counted.where((t) => t.debit)) {
      byCat[t.category ?? 'Uncategorised'] = (byCat[t.category ?? 'Uncategorised'] ?? 0) + t.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _addCash, icon: const Icon(Icons.add), label: const Text('Cash')),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: ListView(padding: pagePadding.copyWith(bottom: 96), children: [
          if (noSources) _SetupCard(onSms: _enableSms, onEmail: () => showMailConnect(context).then((_) => _sync())),
          if (!noSources && !Ledger.smsOn)
            InfoBanner(icon: Icons.sms_outlined, text: 'Add bank SMS for complete tracking.', action: 'Allow', onTap: _enableSms),
          // Hero: month + totals + budget pace
          Card(
            color: cs.primaryContainer.withValues(alpha: 0.55),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 20),
              child: Column(children: [
                Row(children: [
                  IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left)),
                  Expanded(child: Text('${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][_month.month - 1]} ${_month.year}', textAlign: TextAlign.center, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                  IconButton(onPressed: isThisMonth ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right)),
                ]),
                Text('Spent', style: tt.labelLarge?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.8))),
                FittedBox(child: Text(inr(spent), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1, fontFeatures: const [FontFeature.tabularFigures()]))),
                const SizedBox(height: 6),
                Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 6, children: [
                  StatChip(icon: Icons.south_west, label: 'In ${inr(received)}'),
                  StatChip(icon: Icons.balance, label: 'Net ${inr(received - spent, sign: true)}'),
                ]),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: budget <= 0
                      ? OutlinedButton.icon(onPressed: _editBudget, icon: const Icon(Icons.flag_outlined), label: const Text('Set a monthly budget'))
                      : InkWell(
                          onTap: _editBudget,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Column(children: [
                              LinearProgressIndicator(
                                value: (spent / budget).clamp(0, 1),
                                minHeight: 10,
                                borderRadius: BorderRadius.circular(8),
                                color: spent > budget ? cs.error : spent > budget * (isThisMonth ? now.day / daysInMonth : 1) ? Colors.orange : cs.primary,
                              ),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(child: Text('${inr(spent)} of ${inr(budget)}', style: tt.bodySmall)),
                                Text(
                                  spent >= budget
                                      ? 'Over by ${inr(spent - budget)}'
                                      : isThisMonth
                                          ? '${inr((budget - spent) / daysLeft)}/day for $daysLeft days'
                                          : '${inr(budget - spent)} saved',
                                  style: tt.bodySmall?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ]),
                            ]),
                          ),
                        ),
                ),
              ]),
            ),
          ),
          if (isThisMonth && Ledger.all.isNotEmpty) ...[
            BuddyTakeCard(text: _ai ?? _ruleInsight(), loading: _aiLoading, onAsk: _askAi, askLabel: 'Deeper insight', footnote: _ai == null ? '' : 'Only totals were shared, never messages or banks.'),
            const SectionTitle('Last 7 days'),
            AppCard(
              child: WeekBars(
                data: [for (final (d, v) in Ledger.last7()) (weekdayShort(d), v.round())],
                goal: budget > 0 ? (budget / daysInMonth).round() : 0,
                color: cs.primary,
                overIsBad: budget > 0,
                emptyText: 'No spending in the last week.',
              ),
            ),
          ],
          if (cats.isNotEmpty) ...[
            const SectionTitle('Where it went'),
            AppCard(
              child: Column(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Row(children: [
                    for (final (i, e) in cats.take(6).indexed)
                      Expanded(flex: (e.value / spent * 1000).round().clamp(1, 1000), child: Container(height: 12, color: _catColor(cs, i))),
                  ]),
                ),
                const SizedBox(height: 12),
                for (final (i, e) in cats.take(6).indexed)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: _catColor(cs, i), shape: BoxShape.circle)),
                      const SizedBox(width: 10),
                      Text(e.key == 'Uncategorised' ? '❔' : categoryEmoji(e.key)),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e.key)),
                      Text('${(e.value / spent * 100).round()}%', style: tt.bodySmall),
                      const SizedBox(width: 12),
                      SizedBox(width: 84, child: Text(inr(e.value), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()]))),
                    ]),
                  ),
                if (byCat.containsKey('Uncategorised'))
                  Padding(padding: const EdgeInsets.only(top: 6), child: Text('Tip: tap a transaction to give it a category.', style: tt.bodySmall)),
              ]),
            ),
          ],
          SectionTitle(
            'Transactions',
            trailing: _syncing
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : (noSources ? null : TextButton.icon(onPressed: _sync, icon: const Icon(Icons.sync, size: 18), label: const Text('Sync'))),
          ),
          if (txns.isEmpty)
            EmptyState(
              emoji: '🧾',
              title: noSources ? 'Nothing tracked yet' : 'No transactions this month',
              subtitle: noSources ? 'Allow bank SMS or link your email above, or add a cash entry.' : 'Pull down to sync again.',
            ),
          for (final e in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(children: [
                Text(_dayLabel(e.key), style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
                const Spacer(),
                Text(inr(-Ledger.spent(e.value.where((t) => !t.hidden))), style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
            Card(
              margin: const EdgeInsets.symmetric(vertical: 2),
              child: Column(children: [
                for (final t in e.value)
                  ListTile(
                    onTap: () => _openTxn(t),
                    leading: CircleAvatar(
                      backgroundColor: t.debit ? cs.surfaceContainerHighest : gainColor(context, 1).withValues(alpha: 0.15),
                      child: t.category != null
                          ? Text(categoryEmoji(t.category), style: const TextStyle(fontSize: 18))
                          : Icon(t.debit ? Icons.north_east : Icons.south_west, size: 18, color: t.debit ? cs.onSurfaceVariant : gainColor(context, 1)),
                    ),
                    title: Text(t.category ?? (t.debit ? 'Paid' : 'Received'), style: TextStyle(fontWeight: FontWeight.w600, decoration: t.hidden ? TextDecoration.lineThrough : null)),
                    subtitle: Text('${t.bank} · ${_src(t.source)}'),
                    trailing: Text(
                      inr(t.debit ? -t.amount : t.amount, sign: true, decimals: t.amount % 1 == 0 ? 0 : 2),
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: t.hidden ? cs.outline : (t.debit ? cs.onSurface : gainColor(context, 1)), fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
              ]),
            ),
          ],
          if (Ledger.lastSync() != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                'Synced ${_ago(Ledger.lastSync()!)} · ${[if (Ledger.smsOn) 'SMS', if (MailAccount.linked) 'Email'].join(' + ')} · only amounts are read 🔒',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
        ]),
      ),
    );
  }

  static String _ago(DateTime d) {
    final m = DateTime.now().difference(d).inMinutes;
    return m < 1 ? 'just now' : m < 60 ? '$m min ago' : m < 1440 ? '${m ~/ 60} h ago' : '${m ~/ 1440} d ago';
  }

  static Color _catColor(ColorScheme cs, int i) => [cs.primary, cs.tertiary, cs.secondary, Colors.orange, Colors.pinkAccent, cs.outline][i % 6];
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
              child: Text('Buddy reads only the amount, debit/credit, date and bank. Message text, merchants and account numbers are never saved. SMS from people are never read.',
                  style: tt.bodySmall),
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
