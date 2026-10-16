import 'package:flutter/material.dart';

import 'ui/home_screen.dart';

void main() => runApp(const MememaidApp());

const seed = Color(0xFF2ED3B7);

class MememaidApp extends StatelessWidget {
  const MememaidApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return MaterialApp(
      title: 'Mememaid',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: scheme,
        // Thumbnails are the content; a near-black ground keeps them the
        // brightest thing on screen instead of competing with the chrome.
        scaffoldBackgroundColor: const Color(0xFF0E1113),
        useMaterial3: true,
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
