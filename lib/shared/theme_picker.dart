import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/game.dart';

/// Day / night switch: flips the current colour family between its light theme and its dark twin.
class NightModeTile extends StatelessWidget {
  const NightModeTile({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: themeChanges,
        builder: (context, _, _) {
          final day = themeFamily, night = nightOf(day);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              secondary: Icon(nightMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined),
              title: Text(nightMode ? 'Night' : 'Day'),
              subtitle: Text(!night.unlocked
                  ? '${night.name} unlocks at level ${night.unlockLevel}'
                  : nightModeChosen
                      ? '${day.name} by day, ${night.name} by night'
                      : 'Following your phone\'s dark mode'),
              value: nightMode && night.unlocked,
              onChanged: night.unlocked
                  ? (v) {
                      HapticFeedback.selectionClick();
                      setNightMode(v);
                    }
                  : null,
            ),
            if (nightModeChosen)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 60, bottom: 4),
                  child: TextButton.icon(
                    onPressed: () => setNightMode(null),
                    icon: const Icon(Icons.phone_android, size: 16),
                    label: const Text('Follow phone instead'),
                  ),
                ),
              ),
          ]);
        },
      );
}

/// The three colour families (each a day theme with its night twin) plus the day / night switch.
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: themeChanges,
        builder: (context, _, _) {
          final current = themeFamily;
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const NightModeTile(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final day in botColors.where((c) => themePairs.containsKey(c.id)))
                  ChoiceChip(
                    avatar: day.unlocked ? _Swatch(day: day, night: nightOf(day)) : const Icon(Icons.lock, size: 16),
                    label: Text(day.unlocked ? '${day.name} · ${nightOf(day).name}' : '${day.name} · Lv ${day.unlockLevel}'),
                    selected: current.id == day.id,
                    onSelected: day.unlocked
                        ? (_) {
                            HapticFeedback.selectionClick();
                            selectBotTheme(day.id);
                          }
                        : null,
                  ),
              ]),
            ),
          ]);
        },
      );
}

/// Two dots: the family's day colour and its night colour.
class _Swatch extends StatelessWidget {
  final BotColor day, night;
  const _Swatch({required this.day, required this.night});

  Widget _dot(Color fill, Color ring) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: fill, shape: BoxShape.circle, border: Border.all(color: ring, width: 1.5)),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 18,
        height: 18,
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [_dot(day.accent, day.background), _dot(night.accent, night.background)]),
      );
}
