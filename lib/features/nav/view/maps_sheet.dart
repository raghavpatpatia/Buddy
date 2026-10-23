import 'package:flutter/material.dart';

import '../../../core/format.dart';
import '../../../shared/ui.dart';
import '../controller/nav_controller.dart';
import 'area_picker.dart';

void openAreaPicker(BuildContext context, NavController c) => Navigator.push(context, MaterialPageRoute(builder: (_) => AreaPicker(c: c)));

Future<void> showMapsSheet(BuildContext context, NavController c) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MapsSheet(c: c),
    );

/// Maps on this phone: switch, update to the latest weekly build, delete, or download a new area.
class _MapsSheet extends StatelessWidget {
  final NavController c;
  const _MapsSheet({required this.c});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          final latest = c.manifest?.built;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Offline maps', style: tt.titleLarge?.copyWith(fontFamily: hudFont, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Maps are rebuilt from OpenStreetMap every week. Update to get new roads and turn rules.', style: tt.bodySmall),
            const SizedBox(height: 8),
            for (final r in c.regions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(c.region?.id == r.id ? Icons.radio_button_checked : Icons.radio_button_off, color: SystemColors.mana),
                title: Text(r.name),
                subtitle: Text([
                  fmtBytes(r.bytes),
                  '${r.km2.round()} km²',
                  if (r.dataDate.length >= 10) 'data ${r.dataDate.substring(0, 10)}',
                ].join(' · ')),
                onTap: () {
                  c.selectRegion(r);
                  Navigator.pop(context);
                },
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (latest != null && r.built.isNotEmpty && r.built != latest)
                    IconButton(
                      tooltip: 'Update',
                      icon: Icon(Icons.system_update_alt, color: SystemColors.mana),
                      onPressed: c.download != null
                          ? null
                          : () {
                              c.downloadArea(r.box, replacing: r);
                              Navigator.pop(context);
                            },
                    ),
                  IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => c.deleteRegion(r)),
                ]),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: c.download != null
                  ? null
                  : () {
                      final nav = Navigator.of(context)..pop();
                      nav.push(MaterialPageRoute(builder: (_) => AreaPicker(c: c)));
                    },
              icon: const Icon(Icons.add_location_alt_outlined),
              label: const Text('Download a new area'),
            ),
          ]);
        },
      ),
    );
  }
}
