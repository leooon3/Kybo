import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../services/inventory_service.dart';
import '../services/notification_service.dart';
import '../constants.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = "Avvio in corso...";
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // 1. Environment Variables
      try {
        await dotenv.load(fileName: ".env");
      } catch (e) {
        debugPrint("Env Warning: $e");
      }

      // 2. Firebase
      setState(() => _status = "Connessione Cloud...");
      await Firebase.initializeApp();

      // 3. Services & Permissions (BLOCKING)
      setState(() => _status = "Richiesta Permessi...");

      // Initialize Notification Service
      final notifs = NotificationService();
      await notifs.init();

      // Request Permissions explicitly and wait for user input
      await notifs.requestPermissions();

      // Subscribe to topics (safe to do after init)
      try {
        await FirebaseMessaging.instance.subscribeToTopic('all_users');
      } catch (e) {
        debugPrint("Topic Subscribe Error: $e");
      }

      // 4. Load Business Logic
      setState(() => _status = "Caricamento Servizi...");

      // Blocking Inventory init
      await InventoryService.initialize();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _status = "Errore di avvio:\n$e";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/icon.png',
                width: 100,
                height: 100,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.eco, size: 80, color: Colors.white),
              ),
              const SizedBox(height: 24),
              if (_hasError) ...[
                const Icon(
                  Icons.error_outline,
                  size: 48,
                  color: AppColors.secondary,
                ),
                const SizedBox(height: 16),
                Text(
                  _status,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _initializeApp,
                  child: const Text("Riprova"),
                ),
              ] else ...[
                const CircularProgressIndicator(color: Colors.white),
                const SizedBox(height: 16),
                Text(_status, style: const TextStyle(color: Colors.white70)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
