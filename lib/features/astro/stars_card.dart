import 'package:flutter/material.dart';

import 'astro_page.dart';
import 'jyotish.dart';

/// Compact "Today's stars" card for the Buddy home screen.
class StarsCard extends StatefulWidget {
  const StarsCard({super.key});
  @override
  State<StarsCard> createState() => _StarsCardState();
}

class _StarsCardState extends State<StarsCard> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final b = loadBirth();
    String title, sub;
    if (b == null) {
      title = '✨ Your stars';
      sub = 'Add birth details for your Rashi, Nakshatra & daily outlook';
    } else {
      final p = Panchang.at(DateTime.now(), b.lat, b.lon, DateTime.now().timeZoneOffset);
      final o = outlookFor(Chart(b), p);
      title = '${'★' * o.score}${'☆' * (5 - o.score)}  ${o.headline}';
      sub = 'Moon in ${nakshatras[p.nak].name} · ${o.focus.$1}'
          '${p.rahuKaal == null ? '' : '\nRahu Kaal ${hm(p.rahuKaal!.$1)} – ${hm(p.rahuKaal!.$2)}'}';
    }
    return Card(
      color: const Color(0xFF8E24AA).withValues(alpha: 0.12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AstroPage()));
          if (mounted) setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Text('🪐', style: TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Today’s stars', style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
                Text(title, style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: b == null ? null : Colors.amber.shade800)),
                const SizedBox(height: 2),
                Text(sub, style: tt.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ),
    );
  }
}
