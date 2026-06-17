import 'package:flutter/material.dart';

ThemeData appLightTheme() => ThemeData(
  colorSchemeSeed: Colors.teal,
  useMaterial3: true,
  brightness: Brightness.light,
);

ThemeData appDarkTheme() => ThemeData(
  colorSchemeSeed: Colors.teal,
  useMaterial3: true,
  brightness: Brightness.dark,
);
