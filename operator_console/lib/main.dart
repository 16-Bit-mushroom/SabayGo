import 'package:flutter/material.dart';
import 'core/layout/operator_shell.dart';

void main() {
  runApp(const SabayGoOperatorConsole());
}

class SabayGoOperatorConsole extends StatelessWidget {
  const SabayGoOperatorConsole({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SabayGo Operator Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Modern, high-contrast dark theme
        scaffoldBackgroundColor: const Color(0xFF151923), 
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8FBCBB), // Soft Teal Accent
          surface: Color(0xFF222736), // Slightly lighter dark for cards
          error: Color(0xFFBF616A), // Muted red for alerts
        ),
        useMaterial3: true,
      ),
      home: const OperatorShell(),
    );
  }
}