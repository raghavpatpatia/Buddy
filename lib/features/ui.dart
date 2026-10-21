import 'package:flutter/material.dart';

const pagePadding = EdgeInsets.fromLTRB(16, 4, 16, 24);
const brandSeed = Color(0xFF26C6DA);

ThemeData buddyTheme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: brandSeed, brightness: b);
  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    scaffoldBackgroundColor: cs.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: cs.onSurface, letterSpacing: -0.5),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(fontSize: 12, fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    ),
    chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    listTileTheme: const ListTileThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(linearTrackColor: cs.surfaceContainerHighest, circularTrackColor: cs.surfaceContainerHighest),
    bottomSheetTheme: const BottomSheetThemeData(showDragHandle: true),
  );
}

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});
  @override
  Widget build(BuildContext context) =>
      Card(color: color, clipBehavior: Clip.antiAlias, child: Padding(padding: padding, child: child));
}

/// Big centered summary card at the top of a page.
class HeroCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  const HeroCard({super.key, required this.child, this.color});
  @override
  Widget build(BuildContext context) => Card(
        color: color ?? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.55),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24), child: Center(child: child)),
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
