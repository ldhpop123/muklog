import 'package:flutter/material.dart';

const brandColor = Color(0xFFE8572A);

ThemeData buildTheme() {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
    useMaterial3: true,
  );
}
