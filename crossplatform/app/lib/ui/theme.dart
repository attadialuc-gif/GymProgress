import 'package:flutter/material.dart';
import 'package:gym_store/gym_store.dart';

/// Single accent for progress, records and primary actions. Dark by default (port of Theme.swift).
class GymColors {
  static const accent = Color(0xFF4FC3F7);
  static const positive = Color(0xFF66BB6A);
  static const caution = Color(0xFFFFA726);
  static const darkBackground = Color(0xFF0E1116);
  static const darkCard = Color(0xFF1A1F27);
  static const darkElevated = Color(0xFF242A33);
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: GymColors.accent,
    brightness: brightness,
    primary: dark ? GymColors.accent : const Color(0xFF0277BD),
    surface: dark ? GymColors.darkBackground : const Color(0xFFF7F8FA),
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      color: dark ? GymColors.darkCard : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
  );
}

ThemeMode themeMode(AppTheme theme) => switch (theme) {
  AppTheme.dark => ThemeMode.dark,
  AppTheme.light => ThemeMode.light,
  AppTheme.system => ThemeMode.system,
};

/// Rounded container used across the app.
class GymCard extends StatelessWidget {
  const GymCard({super.key, required this.children, this.highlighted = false, this.padding = const EdgeInsets.all(16)});
  final List<Widget> children;
  final bool highlighted;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: highlighted ? BorderSide(color: scheme.primary.withValues(alpha: 0.7), width: 1.5) : BorderSide.none,
      ),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: children),
      ),
    );
  }
}

/// Large numbers for weights and reps (scales with the user's text size).
class BigNumber extends StatelessWidget {
  const BigNumber(this.text, {super.key, this.caption});
  final String text;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
          ),
        ),
        if (caption != null) Text(caption!, style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
      ],
    );
  }
}

class GymBadge extends StatelessWidget {
  const GymBadge(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(99)),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Section header for list screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).hintColor)),
  );
}

/// Centered empty state.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message});
  final IconData icon;
  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 8,
        children: [
          Icon(icon, size: 48, color: theme.hintColor),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null)
            Text(
              message!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  required String action,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String hint = '',
  String action = 'Guardar',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(action)),
      ],
    ),
  );
}
