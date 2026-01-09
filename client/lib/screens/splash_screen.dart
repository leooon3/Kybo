import 'package:flutter/material.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import '../constants.dart'; // Importante per i colori del brand

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    // Attesa minima per mostrare il brand
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final user = AuthService().currentUser;

    if (user != null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
    } else {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Sfondo bianco pulito
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // [FIX] LOGO APP (Assicurati che il file esista in assets!)
            // Se il file si chiama diversamente (es. icon.png), cambia la stringa qui sotto.
            Image.asset(
              'assets/icon/icon.png',
              width: 120,
              height: 120,
              errorBuilder: (context, error, stackTrace) {
                // Fallback nel caso l'immagine non venga trovata (per evitare crash)
                return const Icon(
                  Icons.eco,
                  size: 100,
                  color: AppColors.primary,
                );
              },
            ),

            const SizedBox(height: 30),

            // Loading con colore del brand
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
