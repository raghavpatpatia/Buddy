import 'package:flutter/material.dart';

import '../../../shared/ui.dart';
import '../data/cloud_brain.dart';

/// Cloud brain (Claude on AWS Bedrock): on/off, API key, model, spend limits and usage.
class CloudCard extends StatefulWidget {
  final VoidCallback onChanged;
  const CloudCard({super.key, required this.onChanged});
  @override
  State<CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends State<CloudCard> {
  bool? _hasKey;
  final _keyCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    CloudBrain.instance.apiKey().then((k) => mounted ? setState(() => _hasKey = k != null) : null);
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    super.dispose();
  }

  Future<void> _editLimit(String label, Future<void> Function(double) save, double current) async {
    final ctl = TextEditingController(text: current.toStringAsFixed(2));
    final v = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('$label limit (US\$)'),
        content: TextField(controller: ctl, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(prefixText: '\$ ')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, double.tryParse(ctl.text.trim())), child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (v != null && v >= 0) {
      await save(v);
      setState(() {});
    }
  }

  Widget _meter(String label, double spent, double limit, Future<void> Function(double) save) {
    final tt = Theme.of(context).textTheme;
    final f = limit <= 0 ? 1.0 : (spent / limit).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => _editLimit(label, save, limit),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(label, style: tt.bodyMedium)),
            Text('\$${spent.toStringAsFixed(3)} / \$${limit.toStringAsFixed(2)}', style: tt.bodySmall),
            const SizedBox(width: 4),
            const Icon(Icons.edit, size: 14),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: f, minHeight: 6, borderRadius: BorderRadius.circular(6), color: f >= 1 ? Colors.red : (f > 0.8 ? Colors.orange : null)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final on = CloudBrain.enabled;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.cloud_outlined),
          title: const Text('Cloud brain · Claude on AWS', style: TextStyle(fontWeight: FontWeight.w800)),
          subtitle: const Text('Smarter & faster. Chats go to your AWS account. Stops at your limits.'),
          value: on,
          onChanged: (v) {
            CloudBrain.setEnabled(v);
            setState(() {});
            widget.onChanged();
          },
        ),
        if (on) ...[
          if (_hasKey == true)
            Row(children: [
              const Icon(Icons.key, size: 18, color: Colors.green),
              const SizedBox(width: 6),
              const Expanded(child: Text('Bedrock API key saved (encrypted)')),
              TextButton(
                onPressed: () async {
                  await CloudBrain.instance.setApiKey(null);
                  setState(() => _hasKey = false);
                },
                child: const Text('Remove'),
              ),
            ])
          else
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _keyCtl,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Bedrock API key', isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  if (_keyCtl.text.trim().isEmpty) return;
                  await CloudBrain.instance.setApiKey(_keyCtl.text);
                  _keyCtl.clear();
                  setState(() => _hasKey = true);
                },
                child: const Text('Save'),
              ),
            ]),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [for (final m in cloudModels) ButtonSegment(value: m.id, label: Text(m.label))],
            selected: {CloudBrain.model.id},
            onSelectionChanged: (v) => CloudBrain.setModel(v.first).then((_) => setState(() {})),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('\$${CloudBrain.model.inPerM} in / \$${CloudBrain.model.outPerM} out per million tokens · region ${CloudBrain.region}', style: tt.bodySmall),
          ),
          const SizedBox(height: 8),
          _meter('Today', CloudBrain.spentToday, CloudBrain.dailyLimit, CloudBrain.setDailyLimit),
          _meter('This month', CloudBrain.spentMonth, CloudBrain.monthlyLimit, CloudBrain.setMonthlyLimit),
          if (CloudBrain.instance.lastStatus != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(CloudBrain.instance.lastStatus!, style: tt.bodySmall)),
        ],
      ]),
    );
  }
}
