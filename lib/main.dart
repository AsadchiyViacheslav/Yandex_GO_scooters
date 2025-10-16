import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const YandexScooterApp());
}

class YandexScooterApp extends StatelessWidget {
  const YandexScooterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yandex Scooter Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'YandexSansText',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFCC00), // Yandex Yellow
          primary: const Color(0xFFFFCC00),
          secondary: const Color(0xFF000000),
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFCC00),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: 'YandexSansText',
            ),
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}