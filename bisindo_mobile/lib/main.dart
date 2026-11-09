import 'package:flutter/material.dart';
import 'screens/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BisindoApp());
}

class BisindoApp extends StatelessWidget {
  const BisindoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BISINDO',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF145DA0),
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F8FC),
      ),
      home: const HomePage(),
    );
  }
}