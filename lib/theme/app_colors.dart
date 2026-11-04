import 'package:flutter/material.dart';

/// Every colour the UI uses, defined once for light and dark. Read with
/// `context.c.card`, `context.c.muted`, … so screens follow the active theme.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  final Color bg; // page background
  final Color card; // cards, app bars, dialogs
  final Color border;
  final Color divider;
  final Color text;
  final Color muted;
  final Color faint;
  final Color subtle;
  final Color accent;
  final Color accent2;
  final Color ok;
  final Color okStrong;
  final Color bad;
  final Color badStrong;
  final Color primary; // filled primary buttons
  final Color selected; // selected-row background
  final Color gradEnd; // second colour of background gradients

  const AppColors({
    required this.bg,
    required this.card,
    required this.border,
    required this.divider,
    required this.text,
    required this.muted,
    required this.faint,
    required this.subtle,
    required this.accent,
    required this.accent2,
    required this.ok,
    required this.okStrong,
    required this.bad,
    required this.badStrong,
    required this.primary,
    required this.selected,
    required this.gradEnd,
  });

  static const dark = AppColors(
    bg: Color(0xFF0d1117),
    card: Color(0xFF161b22),
    border: Color(0xFF30363d),
    divider: Color(0xFF21262d),
    text: Color(0xFFc9d1d9),
    muted: Color(0xFF8b949e),
    faint: Color(0xFF6e7681),
    subtle: Color(0xFF484f58),
    accent: Color(0xFF58a6ff),
    accent2: Color(0xFF00a8e8),
    ok: Color(0xFF3fb950),
    okStrong: Color(0xFF238636),
    bad: Color(0xFFf85149),
    badStrong: Color(0xFFda3633),
    primary: Color(0xFF1f6feb),
    selected: Color(0xFF0b2a3a),
    gradEnd: Color(0xFF0b1f33),
  );

  static const light = AppColors(
    bg: Color(0xFFf6f8fa),
    card: Color(0xFFffffff),
    border: Color(0xFFd0d7de),
    divider: Color(0xFFeaeef2),
    text: Color(0xFF1f2328),
    muted: Color(0xFF59636e),
    faint: Color(0xFF818b98),
    subtle: Color(0xFFafb8c1),
    accent: Color(0xFF0969da),
    accent2: Color(0xFF0086c3),
    ok: Color(0xFF1a7f37),
    okStrong: Color(0xFF1f883d),
    bad: Color(0xFFcf222e),
    badStrong: Color(0xFFcf222e),
    primary: Color(0xFF0969da),
    selected: Color(0xFFddf4ff),
    gradEnd: Color(0xFFdcebfa),
  );

  /// This palette with the user's accent colour applied (accent, buttons,
  /// selection highlight). `null` keeps the default blue.
  AppColors withAccent(Color? seed, Brightness brightness) {
    if (seed == null) return this;
    final dark = brightness == Brightness.dark;
    final hsl = HSLColor.fromColor(seed);
    final lifted = hsl.withLightness((hsl.lightness + 0.18).clamp(0.0, 0.72)).toColor();
    final accentColor = dark ? lifted : seed;
    return AppColors(
      bg: bg, card: card, border: border, divider: divider, text: text, muted: muted,
      faint: faint, subtle: subtle, ok: ok, okStrong: okStrong, bad: bad, badStrong: badStrong,
      gradEnd: gradEnd,
      accent: accentColor,
      accent2: accentColor,
      primary: seed,
      selected: Color.alphaBlend(seed.withValues(alpha: dark ? 0.22 : 0.12), bg),
    );
  }

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      card: l(card, other.card),
      border: l(border, other.border),
      divider: l(divider, other.divider),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      faint: l(faint, other.faint),
      subtle: l(subtle, other.subtle),
      accent: l(accent, other.accent),
      accent2: l(accent2, other.accent2),
      ok: l(ok, other.ok),
      okStrong: l(okStrong, other.okStrong),
      bad: l(bad, other.bad),
      badStrong: l(badStrong, other.badStrong),
      primary: l(primary, other.primary),
      selected: l(selected, other.selected),
      gradEnd: l(gradEnd, other.gradEnd),
    );
  }
}

extension AppColorsContext on BuildContext {
  /// The palette for the active (light/dark) theme.
  AppColors get c => Theme.of(this).extension<AppColors>() ?? AppColors.dark;
}
