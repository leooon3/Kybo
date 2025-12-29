import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'constants.dart';
import 'repositories/diet_repository.dart';
import 'providers/diet_provider.dart';
import 'screens/splash_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        Provider(create: (_) => DietRepository()),
        // [FIX] Use ChangeNotifierProvider directly.
        // DietRepository is a singleton service here, so we inject it once.
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
      // Listening to the 'global' config document in Firestore
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('global')
          .snapshots(),
      builder: (context, snapshot) {
        // 1. If loading, show a blank or loading screen
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Check the flag
        bool isMaintenance = false;
        if (snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          isMaintenance = data?['maintenance_mode'] ?? false;
        }

        // 3. If Maintenance is ON -> Show Blocking Screen
        if (isMaintenance) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              backgroundColor: Colors.white,
              body: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 80,
                        color: Colors.orange,
                      ),
                      SizedBox(height: 24),
                      Text(
                        "Under Maintenance",
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),
                      Text(
                        "We are currently updating the servers to serve you better.\nPlease try again in a few minutes.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        // 4. If Maintenance is OFF -> Show the actual App
        return child;
      },
    );
  }
}
