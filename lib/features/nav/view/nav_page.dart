import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/arch/load_state.dart';
import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import '../model/region.dart';
import 'map_screen.dart';
import 'nav_map.dart';
import 'nav_widgets.dart';
import 'maps_sheet.dart';

/// Map tab: download a state or city, pick from/to and get the shortest or fastest route over every street.
class NavPage extends StatefulWidget {
  final NavController? controller;
  const NavPage({super.key, this.controller});
  @override
  State<NavPage> createState() => _NavPageState();
}

class _NavPageState extends State<NavPage> {
  late final c = widget.controller ?? NavController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) WidgetsBinding.instance.addPostFrameCallback((_) => c.start());
  }

  @override
  void dispose() {
    if (widget.controller == null) c.dispose();
    super.dispose();
  }

  void _openMap() => Navigator.push(context, MaterialPageRoute(builder: (_) => MapScreen(c: c)));

  Future<void> _pick(bool isStart) async {
    final res = await pickPlace(context, c, isStart: isStart);
    if (res == null) return;
    isStart ? c.setFrom(res.$1) : c.setTo(res.$1);
    if (c.to != null && c.origin != null) await c.findRoute();
  }

  /// Under a start/target: its address when known, else where you are, else coordinates.
  String _where(Place? p, (double, double)? at, {bool here = false}) {
    if (at == null) return c.gpsProblem ?? 'Finding you…';
    if (here && c.myStreet.isNotEmpty) return 'On ${c.myStreet}';
    if (p != null && p.detail.isNotEmpty) return p.detail;
    return '${at.$1.toStringAsFixed(5)}, ${at.$2.toStringAsFixed(5)}';
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: c, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final dl = c.download;
    return ListView(padding: pagePadding, children: [
      if (c.gpsProblem != null)
        InfoBanner(icon: Icons.location_off, text: c.gpsProblem!, action: 'Allow', onTap: () async {
          await c.startGps();
          if (c.gpsProblem != null) await Geolocator.openAppSettings();
        }),
      if (!c.canRoute)
        InfoBanner(icon: Icons.wifi_off, text: 'You\'re offline. Routing needs internet, or a downloaded area.', action: 'Download', onTap: () => openAreaPicker(context, c)),
      if (c.graph case Failed(:final message)) InfoBanner(icon: Icons.broken_image_outlined, text: message, action: 'Maps', onTap: () => showMapsSheet(context, c)),
      Card(
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: 220,
          child: Stack(children: [
            // Preview only; the full map opens on tap so swiping tabs still works here.
            NavMap(key: ValueKey('${c.region?.id}${c.plan?.metres}${c.online}${c.here != null}'), c: c, interactive: false),
            Positioned.fill(child: Material(color: Colors.transparent, child: InkWell(onTap: _openMap))),
            if (!c.online && c.roads == null)
              const Center(child: Text('The map shows when you\'re online\nor have a downloaded area', textAlign: TextAlign.center)),
            const Positioned(right: 8, top: 8, child: StatChip(icon: Icons.open_in_full, label: 'Open map')),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      AppCard(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(children: [
          ListTile(
            leading: Icon(c.from == null ? Icons.my_location : Icons.trip_origin, color: c.from == null ? SystemColors.mana : const Color(0xFFF472B6)),
            title: Text(c.from?.name ?? 'My location', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(_where(c.from, c.origin, here: c.from == null), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (c.from != null) IconButton(tooltip: 'Use my location', onPressed: () => c.setFrom(null), icon: const Icon(Icons.close)),
              IconButton(tooltip: 'Swap', onPressed: c.to == null ? null : c.swap, icon: const Icon(Icons.swap_vert)),
            ]),
            onTap: c.canRoute ? () => _pick(true) : null,
          ),
          ListTile(
            leading: const Icon(Icons.location_on, color: SystemColors.danger),
            title: Text(c.to?.name ?? 'Where to?', maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Text(c.to == null ? 'Street, place or address' : _where(c.to, (c.to!.lat, c.to!.lon)), maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: c.to == null ? null : IconButton(tooltip: 'Clear pin', onPressed: c.clearTarget, icon: const Icon(Icons.close)),
            onTap: c.canRoute ? () => _pick(false) : null,
          ),
          const SizedBox(height: 4),
          ModeSwitch(c: c),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              onPressed: !c.canRoute || c.to == null || c.route.isLoading ? null : c.findRoute,
              icon: c.route.isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.route),
              label: const Text('Find route'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ),
        ]),
      ),
      if (c.route case Failed(:final message)) Padding(padding: const EdgeInsets.all(8), child: Text(message, style: const TextStyle(color: SystemColors.danger))),
      if (c.plan != null) ...[
        const SizedBox(height: 8),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            RouteSummary(c: c),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(onPressed: _openMap, icon: const Icon(Icons.navigation), label: const Text('Start live map')),
          ]),
        ),
      ],
      // Optional, like Google's offline maps: routing without internet.
      SectionTitle(
        'Offline maps',
        trailing: c.regions.isEmpty ? null : TextButton.icon(onPressed: () => showMapsSheet(context, c), icon: const Icon(Icons.layers_outlined, size: 18), label: const Text('Maps')),
      ),
      if (c.downloadError != null) InfoBanner(icon: Icons.error_outline, text: c.downloadError!, action: 'Retry', onTap: () => openAreaPicker(context, c)),
      if (c.updateAvailable && dl == null)
        InfoBanner(
          icon: Icons.system_update_alt,
          text: 'A newer map of ${c.region!.name} is ready (new roads and turn rules).',
          action: 'Update',
          onTap: () => c.downloadArea(c.region!.box, replacing: c.region),
        ),
      if (dl != null)
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Getting ${dl.name}', style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: dl.step.fraction),
            const SizedBox(height: 6),
            Text('${dl.step.label}${dl.step.fraction == null ? '…' : ' · ${(dl.step.fraction! * 100).round()}%'}', style: tt.bodySmall),
          ]),
        )
      else if (c.regions.isEmpty)
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: const Icon(Icons.download_for_offline_outlined),
            title: const Text('Download an area'),
            subtitle: const Text('Optional: routes then work without internet.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAreaPicker(context, c),
          ),
        )
      else
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(c.graph is Loading ? Icons.hourglass_top : Icons.offline_pin_outlined, color: SystemColors.mana),
            title: Text(c.region?.name ?? 'Pick a map'),
            subtitle: Text(c.graph is Loading ? 'Opening…' : c.online ? 'Used when you\'re offline' : 'Routing offline with this map'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showMapsSheet(context, c),
          ),
        ),
    ]);
  }
}
