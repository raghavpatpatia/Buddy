import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/arch/time_sort.dart';
import 'system_background.dart';

const pagePadding = EdgeInsets.fromLTRB(16, 4, 16, 24);

/// The app palette, set by the selected theme (see botColors in core/game.dart): background, cards, an accent
/// ([mana]), the accent for text and icons ([manaBright]) and a warm second colour ([shadow]).
/// (Names kept from the earlier "System" look.)
class SystemColors {
  static bool light = true;
  static Color void_ = const Color(0xFFF5F7FA);
  static Color panel = const Color(0xFFFFFFFF);
  static Color panelHigh = const Color(0xFFF0F5FB);
  static Color mana = const Color(0xFF2F80C8);
  static Color manaBright = const Color(0xFF1F5F99);
  static Color shadow = const Color(0xFFE8A33D);
  static Color text = const Color(0xFF1F2933);
  static Color muted = const Color(0xFF5F6B7A);
  static const danger = Color(0xFFD64545);

  /// The accent (or [c]) mixed into the background at strength [a].
  static Color tint(double a, [Color? c]) => Color.alphaBlend((c ?? mana).withValues(alpha: a), void_);

  /// Recolours everything for a theme.
  static void apply({required bool light, required Color background, required Color card, required Color accent, required Color bright, required Color flare}) {
    SystemColors.light = light;
    void_ = background;
    panel = card;
    panelHigh = light ? Color.alphaBlend(accent.withValues(alpha: 0.06), card) : Color.alphaBlend(Colors.white.withValues(alpha: 0.04), card);
    mana = accent;
    manaBright = bright;
    shadow = flare;
    text = light ? const Color(0xFF1F2933) : const Color(0xFFE8ECF1);
    muted = light ? const Color(0xFF5F6B7A) : const Color(0xFF9AA5B4);
  }

  /// Readable text on the accent: dark on light accents, white on deeper ones.
  static Color get onMana => mana.computeLuminance() > 0.4 ? const Color(0xFF14181F) : Colors.white;
}

/// Font for titles and numbers: the phone's own clear font, easy to read at any age.
const hudFont = 'Roboto';

/// Buddy is always dark: the System look doesn't exist in daylight. [b] is kept for the old call sites.
ThemeData buddyTheme([Brightness b = Brightness.dark]) {
  final brightness = SystemColors.light ? Brightness.light : Brightness.dark;
  final cs = ColorScheme.fromSeed(seedColor: SystemColors.mana, brightness: brightness).copyWith(
    primary: SystemColors.mana,
    onPrimary: SystemColors.onMana,
    primaryContainer: SystemColors.tint(0.28),
    onPrimaryContainer: SystemColors.light ? SystemColors.manaBright : SystemColors.text,
    secondary: SystemColors.shadow,
    onSecondary: Colors.white,
    secondaryContainer: SystemColors.tint(0.2, SystemColors.shadow),
    onSecondaryContainer: SystemColors.text,
    tertiary: SystemColors.manaBright,
    tertiaryContainer: SystemColors.tint(0.14),
    onTertiaryContainer: SystemColors.text,
    error: SystemColors.danger,
    surface: SystemColors.void_,
    onSurface: SystemColors.text,
    onSurfaceVariant: SystemColors.muted,
    surfaceContainerLowest: SystemColors.void_,
    surfaceContainerLow: SystemColors.panel,
    surfaceContainer: SystemColors.panelHigh,
    surfaceContainerHigh: SystemColors.panelHigh,
    surfaceContainerHighest: SystemColors.tint(0.12),
    outline: SystemColors.light ? const Color(0xFFB8C0CC) : const Color(0xFF3A4556),
    outlineVariant: SystemColors.light ? const Color(0xFFE1E6ED) : const Color(0xFF2A3342),
  );
  // Soft edges: a hairline border in dark themes, none in light ones (cards lift with a gentle shadow instead).
  final edge = SystemColors.light ? BorderSide.none : BorderSide(color: cs.outlineVariant);
  const r10 = BorderRadius.all(Radius.circular(14));
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    brightness: brightness,
    // Transparent so the shared SystemBackground shows behind every page.
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: SystemColors.void_,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      foregroundColor: SystemColors.text,
      systemOverlayStyle: SystemColors.light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      titleTextStyle: TextStyle(fontFamily: hudFont, fontSize: 24, fontWeight: FontWeight.w700, color: SystemColors.text),
    ),
    cardTheme: CardThemeData(
      elevation: SystemColors.light ? 1.5 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      color: SystemColors.panel,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: r10, side: edge),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: SystemColors.tint(0.03).withValues(alpha: 0.95),
      indicatorColor: SystemColors.mana.withValues(alpha: 0.18),
      indicatorShape: RoundedRectangleBorder(borderRadius: r10, side: edge),
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(color: s.contains(WidgetState.selected) ? SystemColors.manaBright : SystemColors.muted)),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: hudFont,
          fontSize: 13,
          color: s.contains(WidgetState.selected) ? SystemColors.manaBright : SystemColors.muted,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w600,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: SystemColors.manaBright,
      unselectedLabelColor: SystemColors.muted,
      indicatorColor: SystemColors.mana,
      dividerColor: cs.outlineVariant,
      labelStyle: const TextStyle(fontFamily: hudFont, fontSize: 15, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontFamily: hudFont, fontSize: 15, fontWeight: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: r10),
        textStyle: const TextStyle(fontFamily: hudFont, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(borderRadius: r10),
        side: BorderSide(color: SystemColors.mana.withValues(alpha: 0.6)),
        foregroundColor: SystemColors.manaBright,
        textStyle: const TextStyle(fontFamily: hudFont, fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: SystemColors.manaBright)),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.all(Radius.circular(8)), side: edge),
      backgroundColor: SystemColors.panel,
      selectedColor: SystemColors.mana.withValues(alpha: 0.22),
    ),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: r10)),
    dialogTheme: DialogThemeData(backgroundColor: SystemColors.panel, shape: RoundedRectangleBorder(borderRadius: r10, side: edge)),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      backgroundColor: SystemColors.panel,
      dragHandleColor: SystemColors.mana.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), side: edge),
    ),
    popupMenuTheme: PopupMenuThemeData(color: SystemColors.panelHigh, shape: RoundedRectangleBorder(borderRadius: r10, side: edge)),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: SystemColors.panelHigh,
      contentTextStyle: TextStyle(color: SystemColors.text),
      shape: RoundedRectangleBorder(borderRadius: r10, side: edge),
    ),
    inputDecorationTheme: InputDecorationTheme(
      enabledBorder: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: SystemColors.mana.withValues(alpha: 0.35))),
      focusedBorder: OutlineInputBorder(borderRadius: r10, borderSide: BorderSide(color: SystemColors.mana, width: 1.6)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: SystemColors.mana, linearTrackColor: SystemColors.tint(0.17), circularTrackColor: SystemColors.tint(0.17)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? SystemColors.manaBright : SystemColors.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? SystemColors.mana.withValues(alpha: 0.45) : SystemColors.tint(0.17)),
    ),
  );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  @override
  Widget build(BuildContext context) =>
      Card(color: color, clipBehavior: Clip.antiAlias, child: SystemFrame(child: Padding(padding: padding, child: child)));
}

/// Big centered summary card at the top of a page.
class HeroCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  const HeroCard({super.key, required this.child, this.color});
  @override
  Widget build(BuildContext context) => Card(
        color: color ?? SystemColors.panelHigh.withValues(alpha: 0.85),
        clipBehavior: Clip.antiAlias,
        child: SystemFrame(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: Center(child: child))),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 4, 6),
        child: Row(children: [
          Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const Spacer(),
          ?trailing,
        ]),
      );
}

class StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const StatChip({super.key, required this.icon, required this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;
  const InfoBanner({super.key, required this.icon, required this.text, required this.action, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(icon, color: cs.onTertiaryContainer),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: cs.onTertiaryContainer))),
          TextButton(onPressed: onTap, child: Text(action)),
        ]),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final String emoji, title, subtitle;
  const EmptyState({super.key, required this.emoji, required this.title, required this.subtitle});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 6),
          Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

/// Simple 7-day bar chart with value labels; shows an empty state when all zero.
class WeekBars extends StatelessWidget {
  final List<(String label, num value)> data;
  final num goal;
  final Color color;
  final bool overIsBad;
  final String emptyText;
  const WeekBars({super.key, required this.data, required this.goal, required this.color, this.overIsBad = false, required this.emptyText});

  @override
  Widget build(BuildContext context) {
    if (data.every((d) => d.$2 == 0)) {
      return EmptyState(emoji: '📊', title: 'No data yet', subtitle: emptyText);
    }
    final maxV = data.fold<num>(goal, (m, d) => d.$2 > m ? d.$2 : m);
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (i, (label, v)) in data.indexed)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '$v', style: TextStyle(fontSize: 10, color: muted)),
              const SizedBox(height: 2),
              Container(
                height: (110 * v / maxV).clamp(4, 110).toDouble(),
                margin: const EdgeInsets.symmetric(horizontal: 5),
                decoration: BoxDecoration(
                  color: overIsBad
                      ? (v > goal ? Colors.redAccent : color)
                      : (v >= goal ? color : color.withValues(alpha: 0.45)),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 4),
              Text(i == data.length - 1 ? 'Today' : label,
                  style: TextStyle(fontSize: 11, color: muted, fontWeight: i == data.length - 1 ? FontWeight.w700 : null)),
            ]),
          ),
      ]),
    );
  }
}

String weekdayShort(DateTime d) => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];

/// Compact "sort by" menu for a list; [labels] names each order the list offers.
class SortButton extends StatelessWidget {
  final TimeSort value;
  final Map<TimeSort, String> labels;
  final ValueChanged<TimeSort> onChanged;
  const SortButton({super.key, required this.value, required this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<TimeSort>(
      tooltip: 'Sort',
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (_) => [
        for (final MapEntry(key: s, value: label) in labels.entries) CheckedPopupMenuItem(value: s, checked: s == value, child: Text(label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.swap_vert, size: 18, color: cs.primary),
          const SizedBox(width: 4),
          Text(labels[value]!, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary)),
        ]),
      ),
    );
  }
}
