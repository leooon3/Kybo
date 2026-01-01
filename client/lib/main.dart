import 'dart:async'; // [IMPORT NEEDED FOR TIMER]
import 'package:Kybo/core/env.dart';
import 'package:Kybo/firebase_options_dev.dart' as dev;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options_dev.dart';

import 'constants.dart';
import 'firebase_options_dev.dart' as prod;
import 'repositories/diet_repository.dart';
import 'providers/diet_provider.dart';
import 'screens/splash_screen.dart';
import 'guards/password_guard.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await NotificationService().init();
  await Env.init();

  final firebaseOptions = Env.isProd
      ? prod.DefaultFirebaseOptions.currentPlatform
      : dev.DefaultFirebaseOptions.currentPlatform;

  await Firebase.initializeApp(options: firebaseOptions);

  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DietRepository()),
        ChangeNotifierProvider<DietProvider>(
          create: (context) => DietProvider(context.read<DietRepository>()),
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
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          color: AppColors.surface,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.inputFill,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      builder: (context, child) {
        // [UPDATE] Using the Stateful Guard with Timer
        return MaintenanceGuard(child: PasswordGuard(child: child!));
      },
      home: const SplashScreen(),
    );
  }
}

// -------------------------------------------------------
// 🛡️ MAINTENANCE GUARD WIDGET
// -------------------------------------------------------
class MaintenanceGuard extends StatelessWidget {
  final Widget child;

  const MaintenanceGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('global')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return child;
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;

        // SECURE: We only trust the server's boolean flag.
        bool isMaintenance = data?['maintenance_mode'] ?? false;

        if (isMaintenance) {
          return Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.build_circle,
                    size: 80,
                    color: Colors.orange,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "Under Maintenance",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Text(
                      data?['maintenance_message'] ??
                          "We are updating the system. Please wait.",
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return child;
      },
    );
  }
}
