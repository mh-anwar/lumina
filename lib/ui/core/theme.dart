import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Corner radii: small for controls, medium for tiles and cards.
const radiusSmall = 8.0, radiusMedium = 12.0;

/// Lumina's palette: neutral system grays, light or black. Lights that are
/// off are muted gray tiles; lights that are on are bright tiles ([litTile])
/// tinted with their own color ([lookColor]).
@immutable
class Palette extends ThemeExtension<Palette> {
  final Color bg, surface, text, muted, line, off, danger, on;
  const Palette({
    required this.bg,
    required this.surface,
    required this.text,
    required this.muted,
    required this.line,
    required this.off,
    required this.danger,
    this.on = const Color(0xFFF0A03C),
  });

  static const dark = Palette(
    bg: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    text: Color(0xFFF2F2F7),
    muted: Color(0xFF8E8E93),
    line: Color(0xFF2C2C2E),
    off: Color(0xFF2C2C2E),
    danger: Color(0xFFFF6961),
  );

  static const light = Palette(
    bg: Color(0xFFF2F2F7),
    surface: Color(0xFFFFFFFF),
    text: Color(0xFF1C1C1E),
    muted: Color(0xFF6C6C70),
    line: Color(0xFFE5E5EA),
    off: Color(0xFFE5E5EA),
    danger: Color(0xFFD70015),
  );

  static Palette of(BuildContext context) => Theme.of(context).extension<Palette>()!;

  @override
  Palette copyWith() => this;

  @override
  Palette lerp(Palette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Palette(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      off: l(off, other.off),
      danger: l(danger, other.danger),
      on: l(on, other.on),
    );
  }
}

/// Titles: the body typeface, bold and slightly tightened.
TextStyle display(double size, {Color? color}) => GoogleFonts.figtree(
  fontSize: size,
  fontWeight: FontWeight.w700,
  height: 1.15,
  letterSpacing: -0.3,
  color: color,
);

/// A tile that's on: nearly white in both themes, with a hint of its light's
/// color, so on and off read at a glance.
Color litTile(Color light) => Color.alphaBlend(light.withValues(alpha: 0.14), Colors.white);

/// Text on a [litTile], which is light in both themes.
const litText = Color(0xFF1C1C1E), litMuted = Color(0xFF5C5C61);

ThemeData buildTheme(Brightness b) {
  final p = b == Brightness.dark ? Palette.dark : Palette.light;
  final base = ThemeData(
    brightness: b,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8E8E93), brightness: b).copyWith(
      surface: p.surface,
      onSurface: p.text,
      primary: p.text,
      onPrimary: p.bg,
      onSurfaceVariant: p.muted,
      error: p.danger,
      outline: p.line,
    ),
    scaffoldBackgroundColor: p.bg,
    extensions: [p],
  );
  final text = GoogleFonts.figtreeTextTheme(base.textTheme)
      .apply(bodyColor: p.text, displayColor: p.text);
  return base.copyWith(
    textTheme: text,
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusMedium)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radiusSmall)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    dividerColor: p.line,
    iconTheme: IconThemeData(color: p.text),
    listTileTheme: ListTileThemeData(iconColor: p.muted, textColor: p.text),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.text,
        foregroundColor: p.bg,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.text,
        side: BorderSide(color: p.line),
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSmall)),
        textStyle: GoogleFonts.figtree(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.text : p.off,
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.bg : p.muted,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.text : p.line,
      ),
    ),
  );
}

/// Approximate RGB of a black-body color temperature (Tanner Helland).
Color kelvinColor(int k) {
  final t = k / 100;
  double r, g, b;
  r = t <= 66 ? 255 : 329.698727446 * math.pow(t - 60, -0.1332047592);
  g = t <= 66
      ? 99.4708025861 * math.log(t) - 161.1195681661
      : 288.1221695283 * math.pow(t - 60, -0.0755148492);
  b = t >= 66
      ? 255
      : t <= 19
      ? 0
      : 138.5177312231 * math.log(t - 10) - 305.0447927307;
  int c(double v) => v.round().clamp(0, 255);
  return Color.fromARGB(255, c(r), c(g), c(b));
}

/// The color a light shows: its hue when it's in color, else its white.
Color lookColor({required int kelvin, int? hue, int saturation = 100}) => hue == null
    ? kelvinColor(kelvin)
    : HSVColor.fromAHSV(1, (hue % 360).toDouble(), saturation.clamp(0, 100) / 100, 1).toColor();
