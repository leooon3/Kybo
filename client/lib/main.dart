import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kybo/repositories/diet_repository.dart';
import 'package:kybo/services/auth_service.dart';
import 'package:kybo/services/firestore_service.dart';
import 'package:kybo/services/storage_service.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'core/env.dart';
import 'core/di/locator.dart'; // <--- IMPORTANTE
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;
import 'providers/diet_provider.dart';
import 'screens/splash_screen.dart';
import 'guards/password_guard.dart';
import 'services/notification_service.dart';
import 'constants.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'l10n/generated/app_localizations.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 1. Env & Service Locator
      await Env.init();
      setupLocator(); // <--- INIZIALIZZA I SERVIZI QUI

      // 2. Init Firebase
      try {
        final firebaseOptions = Env.isProd
            ? prod.DefaultFirebaseOptions.currentPlatform
            : dev.DefaultFirebaseOptions.currentPlatform;

        if (Firebase.apps.isEmpty) {
          await Firebase.initializeApp(options: firebaseOptions);
        }

        FirebaseFirestore.instance.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } catch (e) {
        debugPrint("⚠️ Firebase Init Error: $e");
      }

      // 3. Avvio UI con Injection
      runApp(
        MultiProvider(
          providers: [
            // Ora DietProvider riceve le dipendenze dal Locator (getIt)
            // Non creiamo più DietRepository 'volante' qui dentro
            ChangeNotifierProvider<DietProvider>(
              create: (_) => DietProvider(
                repository: getIt<DietRepository>(),
                storage: getIt<StorageService>(),
                firestore: getIt<FirestoreService>(),
                auth: getIt<AuthService>(),
              ),
            ),
          ],
          child: const DietApp(),
        ),
      );

      // 4. Avvio Notifiche
      Future.delayed(const Duration(seconds: 3), () {
        if (Firebase.apps.isNotEmpty) {
          // Usiamo l'istanza singleton, non una nuova
          getIt<NotificationService>().init();
        }
      });
    },
    (error, stack) {
      debugPrint("🔴 Global Error: $error");
    },
  );
}

class DietApp extends StatelessWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kybo',
      localizationsDelegates: const [
        AppLocalizations.delegate, // <-- Il tuo delegato
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it'), // Italiano
        // Locale('en'), // Inglese (quando farai il file app_en.arb)
      ],
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.scaffoldBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.surface,
        ),
      ),
      builder: (context, child) {
        return MaintenanceGuard(child: PasswordGuard(child: child!));
      },
      home: const SplashScreen(),
    );
  }
}

// -------------------------------------------------------
// 🛡️ MAINTENANCE GUARD (SOLO FIRESTORE)
// -------------------------------------------------------
class MaintenanceGuard extends StatelessWidget {
  final Widget child;
  const MaintenanceGuard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Firebase.apps.isEmpty) return child;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('config')
          .doc('global')
          .snapshots(),
      builder: (context, snapshot) {
        // Se siamo offline, Firestore proverà a usare la cache.
        // Se non ha cache o c'è errore, snapshot.hasError potrebbe essere true o connectionState waiting.
        // IN OGNI CASO DI DUBBIO -> Lasciamo passare l'utente (Fail Open)

        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          // Non blocchiamo l'utente se non riusciamo a leggere la config
          return child;
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
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
                    "Manutenzione",
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      data?['maintenance_message'] ??
                          "Sistema in aggiornamento.",
                      textAlign: TextAlign.center,
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
