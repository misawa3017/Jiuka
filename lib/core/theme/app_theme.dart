import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static final TextTheme _textTheme = GoogleFonts.interTextTheme();

  static ThemeData LightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F46E5), // Indigo 600
        secondary: const Color(0xFF0EA5E9), // Sky 500
        tertiary: const Color(0xFF14B8A6), // Teal 500
        surface: const Color(0xFFF8FAFC), // Slate 50
      ),
      textTheme: _textTheme,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData DarkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.dark,
        seedColor: const Color(0xFF6366F1), // Indigo 500
        secondary: const Color(0xFF38BDF8), // Sky 400
        tertiary: const Color(0xFF2DD4BF), // Teal 400
        surface: const Color(0xFF0F172A), // Slate 900
      ),
      textTheme: _textTheme.apply(
        bodyColor: const Color(0xFFF1F5F9), // Slate 100
        displayColor: const Color(0xFFF1F5F9),
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
