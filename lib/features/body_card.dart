import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/health.dart';
import '../core/store.dart';
import 'ui.dart';

/// BMI, healthy range, and where today's calorie target comes from. Asks for height/sex if missing.
class BodyCard extends StatefulWidget {
  final int burned;
  final VoidCallback? onChanged;
  const BodyCard({super.key, this.burned = 0, this.onChanged});
  @override
  State<BodyCard> createState() => _BodyCardState();
}

class _BodyCardState extends State<BodyCard> {
  Future<void> _saveProfile(Map<String, dynamic> changes) async {
    final p = Store.profile..addAll(changes);
    await Store.setProfile(p);
    setState(() {});
    widget.onChanged?.call();
  }

  Future<void> _editWeight() async {
    final c = TextEditingController(text: '${Store.profile['weight']}');
    final v = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Today’s weight'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(suffixText: 'kg', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, double.tryParse(c.text)), child: const Text('Save')),
        ],
      ),
    );
    if (v == null || v < 25 || v > 300) return;
    final log = List<Map<String, dynamic>>.from((Store.getJson('weight_log', []) as List).map((e) => Map<String, dynamic>.from(e)))
      ..removeWhere((e) => e['date'] == dayKey())
      ..add({'date': dayKey(), 'kg': v});
    await Store.setJson('weight_log', log);
    await _saveProfile({'weight': double.parse(v.toStringAsFixed(1))});
  }

  @override
  Widget build(BuildContext context) {
    final body = Body.fromProfile();
    return body == null ? _setup(context) : _summary(context, body);
  }

  Widget _setup(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final p = Store.profile;
    final h = TextEditingController(text: p['heightCm']?.toString() ?? '');
    final y = TextEditingController(text: p['birthYear']?.toString() ?? '');
    var sex = p['sex'] as String?;
    final needsAge = Body.ageYears() == null;
    return StatefulBuilder(
      builder: (context, set) => Card(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Personalise your targets', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Height, sex${needsAge ? ' and birth year' : ''} let Buddy calculate your BMI and real calorie needs instead of a rough guess.',
                style: tt.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: h,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Height', suffixText: 'cm', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              if (needsAge) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: y,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    decoration: const InputDecoration(labelText: 'Birth year', border: OutlineInputBorder(), isDense: true, counterText: ''),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'male', label: Text('Male')), ButtonSegment(value: 'female', label: Text('Female'))],
              selected: {?sex},
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              onSelectionChanged: (v) => set(() => sex = v.isEmpty ? null : v.first),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                final hc = double.tryParse(h.text), yr = int.tryParse(y.text);
                if (hc == null || hc < 120 || hc > 230 || sex == null || (needsAge && (yr == null || yr < 1920 || yr > DateTime.now().year - 10))) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter height in cm (120–230), choose sex and a valid birth year')));
                  return;
                }
                HapticFeedback.mediumImpact();
                _saveProfile({'heightCm': hc, 'sex': sex, if (needsAge) 'birthYear': yr});
              },
              child: const Text('Calculate my BMI & targets'),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _summary(BuildContext context, Body b) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final (label, color, advice) = b.bmiCategory;
    final (lo, hi) = b.healthyRange;
    final goal = Store.profile['goal'] as String? ?? 'maintain';
    final t = DailyTargets.today(burned: widget.burned);
    const goalNames = {'lose': 'Lose fat', 'maintain': 'Maintain', 'gain': 'Build muscle'};
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Your body', style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          TextButton.icon(onPressed: _editWeight, icon: const Icon(Icons.monitor_weight_outlined, size: 18), label: Text('${Store.profile['weight']} kg')),
        ]),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(b.bmi.toStringAsFixed(1), style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w900, color: color)),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('BMI · $label', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ),
        ]),
        const SizedBox(height: 6),
        _BmiScale(bmi: b.bmi),
        const SizedBox(height: 8),
        Text('Healthy for ${b.heightCm.round()} cm: ${lo.toStringAsFixed(0)}–${hi.toStringAsFixed(0)} kg (Indian cut-offs). $advice', style: tt.bodySmall),
        if (b.suggestedGoal != goal) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Expanded(child: Text('Suggested goal: ${goalNames[b.suggestedGoal]}', style: const TextStyle(fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => _saveProfile({'goal': b.suggestedGoal}), child: const Text('Switch')),
            ]),
          ),
        ],
        const Divider(height: 24),
        Text('Today’s calories: ${t.kcal} kcal', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          'BMR ${b.bmr.round()} × 1.2 (daily life) = ${t.baseline}'
          '${t.burned > 0 ? ' + ${t.burned} burned today' : ''}'
          '${t.adjust != 0 ? ' ${t.adjust > 0 ? '+' : '−'} ${t.adjust.abs()} (${goalNames[goal]})' : ''}',
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        Text('Protein ${t.protein.round()} g · Carbs ${t.carbs.round()} g · Fat ${t.fat.round()} g · Fibre ${t.fiber.round()} g',
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// Coloured BMI scale (Asian cut-offs) with a marker at the current value.
class _BmiScale extends StatelessWidget {
  final double bmi;
  const _BmiScale({required this.bmi});
  static const _min = 15.0, _max = 35.0;
  @override
  Widget build(BuildContext context) {
    double f(double v) => ((v - _min) / (_max - _min)).clamp(0, 1);
    return LayoutBuilder(builder: (_, box) {
      final w = box.maxWidth;
      return SizedBox(
        height: 30,
        child: Stack(children: [
          Positioned(
            top: 6,
            left: 0,
            right: 0,
            height: 10,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(children: [
                Expanded(flex: ((18.5 - _min) * 10).round(), child: Container(color: Colors.blue)),
                Expanded(flex: ((23 - 18.5) * 10).round(), child: Container(color: Colors.green)),
                Expanded(flex: ((25 - 23) * 10).round(), child: Container(color: Colors.orange)),
                Expanded(flex: ((_max - 25) * 10).round(), child: Container(color: Colors.red)),
              ]),
            ),
          ),
          Positioned(
            left: f(bmi) * w - 7,
            top: 0,
            child: Container(
              width: 14,
              height: 22,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(color: Theme.of(context).colorScheme.onSurface, width: 2),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
          for (final (v, s) in [(18.5, '18.5'), (23.0, '23'), (25.0, '25')])
            Positioned(left: f(v) * w - 12, top: 18, width: 24, child: Text(s, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9))),
        ]),
      );
    });
  }
}
