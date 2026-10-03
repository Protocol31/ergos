import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta tomada de las referencias: bosque profundo, musgo, eucalipto,
/// salvia, liquen y el destello amarillo-lima de la luz del vitral.
class Ergos {
  static const deepForest = Color(0xFF022E24);
  static const night = Color(0xFF01180F);
  static const moss = Color(0xFF1F4D3A);
  static const eucalyptus = Color(0xFF4F8F75);
  static const sage = Color(0xFF9FC3B2);
  static const lichen = Color(0xFFE7F1EC);
  static const glow = Color(0xFFE6F58A); // la luz: "ERGOS"
  static const lead = Color(0xFF04120C); // emplomado del vitral
  static const danger = Color(0xFFD98C7E);

  static ThemeData theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: eucalyptus,
      brightness: Brightness.dark,
    ).copyWith(
      surface: deepForest,
      primary: glow,
      onPrimary: night,
      secondary: sage,
      onSurface: lichen,
      error: danger,
    );
    final serif = GoogleFonts.cormorantGaramondTextTheme(ThemeData.dark().textTheme);
    final sans = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);
    final text = sans.copyWith(
      displayLarge: serif.displayLarge?.copyWith(color: lichen, fontWeight: FontWeight.w500),
      displayMedium: serif.displayMedium?.copyWith(color: lichen, fontWeight: FontWeight.w500),
      headlineLarge: serif.headlineLarge?.copyWith(color: lichen, fontWeight: FontWeight.w600),
      headlineMedium: serif.headlineMedium?.copyWith(color: lichen, fontWeight: FontWeight.w600),
      titleLarge: serif.titleLarge?.copyWith(color: lichen, fontWeight: FontWeight.w600, fontSize: 24),
    ).apply(bodyColor: lichen, displayColor: lichen);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: night,
      textTheme: text,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: moss.withOpacity(.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: sage.withOpacity(.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: sage.withOpacity(.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: glow, width: 1.4),
        ),
        labelStyle: const TextStyle(color: sage),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: glow,
          foregroundColor: night,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: sage,
          side: BorderSide(color: sage.withOpacity(.4)),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: glow.withOpacity(.16),
        selectedIconTheme: const IconThemeData(color: glow),
        unselectedIconTheme: IconThemeData(color: sage.withOpacity(.8)),
        selectedLabelTextStyle: const TextStyle(color: glow),
        unselectedLabelTextStyle: TextStyle(color: sage.withOpacity(.8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: night.withOpacity(.85),
        indicatorColor: glow.withOpacity(.16),
      ),
      dividerColor: sage.withOpacity(.15),
    );
  }
}
