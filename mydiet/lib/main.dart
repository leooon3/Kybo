import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'repositories/diet_repository.dart';
import 'providers/diet_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'services/inventory_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // [FIX] Safe .env loading. Prevents crash if file is missing (e.g., in CI/CD or Prod)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint(
      "⚠️ Warning: .env file not found. Ensure environment variables are set.",
    );
  }

  try {
    await Firebase.initializeApp();
    // Optional: Subscribe only if platform supports it or after permission check
    await FirebaseMessaging.instance.subscribeToTopic('all_users');
  } catch (e) {
    debugPrint("⚠️ Firebase Init Error: $e");
  }

  try {
    final notifs = NotificationService();
    await notifs.init();
    await notifs.requestPermissions();
  } catch (e) {
    debugPrint("⚠️ Notification Init Error: $e");
  }

  // Init Background Tasks
  await InventoryService.initialize();

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DietRepository()),
        ChangeNotifierProxyProvider<DietRepository, DietProvider>(
          create: (context) => DietProvider(context.read<DietRepository>()),
          update: (context, repo, prev) => prev ?? DietProvider(repo),
        ),
      ],
      child: const DietApp(),
    ),
  );
}

class DietApp extends StatelessWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyDiet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // Primary Green
          secondary: const Color(0xFFE65100), // Accent Orange
          surface: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey[100],
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}
