import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/system_background.dart';
import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import '../model/region.dart';
import '../model/road_graph.dart' show metres;
import '../model/route_plan.dart';

/// "You" and "Target", always shown together with the distance between them.
class EndsCard extends StatelessWidget {
  final NavController c;
  const EndsCard({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final s = c.origin;
    final youTitle = c.from?.name ?? (c.myStreet.isNotEmpty ? c.myStreet : 'My location');
    final youSub = s == null ? (c.gpsProblem ?? 'Finding you…') : '${s.$1.toStringAsFixed(5)}, ${s.$2.toStringAsFixed(5)}';
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        children: [
          _End(
            icon: c.from == null ? Icons.my_location : Icons.trip_origin,
            color: c.from == null ? SystemColors.mana : const Color(0xFFF472B6),
            label: 'YOU',
            title: youTitle,
            sub: youSub,
          ),
          const Divider(height: 14),
          _End(
            icon: Icons.location_on,
            color: SystemColors.danger,
            label: 'TARGET',
            title: c.to?.name ?? 'Not set',
            sub: c.to == null ? 'Search a place or long-press the map' : c.to!.coords,
          ),
        ],
      ),
    );
  }
}

class _End extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label, title, sub;
  const _End({required this.icon, required this.color, required this.label, required this.title, required this.sub});
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: tt.labelSmall?.copyWith(fontFamily: hudFont, letterSpacing: 1.2, color: color),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Distance left (live), total, time and what the route uses.
class RouteSummary extends StatelessWidget {
  final NavController c;

  /// On the live map: leave out the street list so the map stays visible.
  final bool compact;
  const RouteSummary({super.key, required this.c, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final plan = c.plan;
    if (plan == null) return const SizedBox.shrink();
    final left = c.progress?.metresLeft ?? plan.metres;
    final secsLeft = plan.metres == 0 ? 0.0 : plan.seconds * left / plan.metres;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              c.arrived ? 'Arrived' : fmtKm(left),
              style: tt.displaySmall?.copyWith(fontFamily: hudFont, fontWeight: FontWeight.w700, color: SystemColors.manaBright),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(c.arrived ? '🎯' : 'to go · ${fmtEta(secsLeft)}', style: tt.bodyMedium),
            ),
            if (c.route.isLoading) ...[
              const Spacer(),
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            StatChip(icon: Icons.straighten, label: 'Total ${fmtKm(plan.metres)}'),
            StatChip(icon: Icons.schedule, label: fmtEta(plan.seconds)),
            if (plan.flyovers > 0) StatChip(icon: Icons.alt_route, label: '${plan.flyovers} flyover${plan.flyovers == 1 ? '' : 's'}'),
            if (plan.tunnels > 0) StatChip(icon: Icons.subway_outlined, label: '${plan.tunnels} tunnel${plan.tunnels == 1 ? '' : 's'}'),
            StatChip(icon: c.online ? Icons.wifi : Icons.wifi_off, label: c.online ? 'Online map' : 'Offline map'),
          ],
        ),
        if (plan.streets.isNotEmpty && !compact) ...[
          const SizedBox(height: 8),
          Text(
            'Via ${plan.streets.take(6).join(' → ')}${plan.streets.length > 6 ? ' …' : ''}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: tt.bodySmall,
          ),
        ],
        if (c.alternatives.isNotEmpty || c.findingAlternatives) ...[
          const SizedBox(height: 8),
          // One swipeable row on the live map, wrapped rows elsewhere.
          if (compact)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < c.alternatives.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ActionChip(
                        avatar: const Icon(Icons.alt_route, size: 16),
                        label: Text(_altLabel(plan, c.alternatives[i])),
                        onPressed: () => c.chooseAlternative(i),
                      ),
                    ),
                  if (c.findingAlternatives) Text('Finding other routes…', style: tt.bodySmall),
                ],
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < c.alternatives.length; i++)
                  ActionChip(
                    avatar: const Icon(Icons.alt_route, size: 16),
                    label: Text(_altLabel(plan, c.alternatives[i])),
                    onPressed: () => c.chooseAlternative(i),
                  ),
                if (c.findingAlternatives) Text('Finding other routes…', style: tt.bodySmall),
              ],
            ),
        ],
      ],
    );
  }

  /// "+4 min · 21.7 km" relative to the chosen route.
  static String _altLabel(RoutePlan best, RoutePlan alt) {
    final d = ((alt.seconds - best.seconds) / 60).round();
    return '${d == 0
        ? 'Same time'
        : d > 0
        ? '+$d min'
        : '−${-d} min'} · ${fmtKm(alt.metres)}';
  }
}

/// Google-style next-turn banner: arrow, distance to the turn, instruction.
class ManeuverBanner extends StatelessWidget {
  final NavController c;
  const ManeuverBanner({super.key, required this.c});

  static IconData iconFor(Turn t) => switch (t) {
    Turn.depart || Turn.straight => Icons.straight,
    Turn.slightLeft => Icons.turn_slight_left,
    Turn.slightRight => Icons.turn_slight_right,
    Turn.left => Icons.turn_left,
    Turn.right => Icons.turn_right,
    Turn.sharpLeft => Icons.turn_sharp_left,
    Turn.sharpRight => Icons.turn_sharp_right,
    Turn.uTurn => Icons.u_turn_left,
    Turn.roundabout => Icons.roundabout_left,
    Turn.flyover => Icons.alt_route,
    Turn.arrive => Icons.flag,
  };

  @override
  Widget build(BuildContext context) {
    final m = c.nextManeuver, d = c.toNextManeuver;
    if (m == null || d == null || c.arrived) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Card(
      color: SystemColors.panelHigh.withValues(alpha: 0.95),
      child: SystemFrame(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(
            children: [
              Icon(iconFor(m.turn), size: 40, color: SystemColors.manaBright),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fmtKm(d),
                      style: tt.headlineSmall?.copyWith(fontFamily: hudFont, fontWeight: FontWeight.w700),
                    ),
                    Text(m.text, maxLines: 2, overflow: TextOverflow.ellipsis, style: tt.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fastest / Shortest switch.
class ModeSwitch extends StatelessWidget {
  final NavController c;
  const ModeSwitch({super.key, required this.c});
  @override
  Widget build(BuildContext context) => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(value: true, icon: Icon(Icons.bolt, size: 18), label: Text('Fastest')),
      ButtonSegment(value: false, icon: Icon(Icons.straighten, size: 18), label: Text('Shortest')),
    ],
    selected: {c.fastest},
    onSelectionChanged: (s) => c.setFastest(s.first),
  );
}

/// Search sheet for a start or target; returns the chosen place, or (for the start) null = my location.
Future<(Place?,)?> pickPlace(BuildContext context, NavController c, {required bool isStart}) => showModalBottomSheet<(Place?,)>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _PlaceSheet(c: c, isStart: isStart),
);

class _PlaceSheet extends StatefulWidget {
  final NavController c;
  final bool isStart;
  const _PlaceSheet({required this.c, required this.isStart});
  @override
  State<_PlaceSheet> createState() => _PlaceSheetState();
}

class _PlaceSheetState extends State<_PlaceSheet> {
  Timer? _debounce;
  List<Place> _hits = const [];
  bool _busy = false, _searched = false;
  int _ticket = 0;

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () async {
      final t = ++_ticket;
      setState(() => _busy = true);
      final hits = await widget.c.search(q);
      if (!mounted || t != _ticket) return;
      setState(() {
        _hits = hits;
        _busy = false;
        _searched = q.trim().length >= 2;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        // Shrinks while the keyboard is up, so results and the field never overlap.
        height: min(
          MediaQuery.sizeOf(context).height * 0.7,
          (MediaQuery.sizeOf(context).height - MediaQuery.viewInsetsOf(context).bottom) * 0.9,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _busy
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  hintText: widget.isStart ? 'Start: street, place or address' : 'Target: street, place or address',
                  helperMaxLines: 3,
                  helperText: c.online
                      ? 'Places near you${c.roads != null ? ', plus streets in ${c.region?.name}' : ''}'
                      : c.roads != null
                      ? 'Offline: street names in ${c.region?.name}'
                      : 'Offline: connect to the internet to search',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  if (widget.isStart)
                    ListTile(
                      leading: Icon(Icons.my_location, color: SystemColors.mana),
                      title: const Text('My location'),
                      subtitle: Text(c.me == null ? (c.gpsProblem ?? 'Waiting for GPS…') : 'Follows you as you move'),
                      onTap: () => Navigator.pop(context, (null,)),
                    ),
                  if (_searched && !_busy && _hits.isEmpty)
                    ListTile(
                      leading: const Icon(Icons.search_off),
                      title: const Text('No matches'),
                      subtitle: Text(
                        widget.isStart
                            ? 'Try another name, or use My location.'
                            : 'Try another name, or long-press the live map to drop a pin. Some businesses aren\'t on OpenStreetMap.',
                      ),
                    ),
                  for (final p in _hits)
                    ListTile(
                      leading: Icon(p.detail.startsWith('Street') ? Icons.signpost_outlined : Icons.place_outlined),
                      title: Text(p.name),
                      subtitle: Text(
                        [
                          if (c.origin != null) fmtKm(metres(c.origin!.$1, c.origin!.$2, p.lat, p.lon)),
                          if (p.detail.isNotEmpty) p.detail,
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.pop(context, (p,)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
