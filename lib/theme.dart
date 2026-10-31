import 'package:flutter/material.dart';

class C {
  static const yellow = Color(0xFFF4C20D);
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);
  static const grey = Color(0xFFF3F3F3);

}

ThemeData appTheme() => ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: C.yellow,
        primary: C.yellow,
        onPrimary: C.black,
        secondary: C.black,
        surface: C.white,
      ),
      scaffoldBackgroundColor: C.white,
      appBarTheme: const AppBarTheme(
          backgroundColor: C.white, foregroundColor: C.black, elevation: 0, centerTitle: true),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: C.grey,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: C.yellow, width: 2)),
      ),
    );
