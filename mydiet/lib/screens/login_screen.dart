import 'package:flutter/material.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final AuthService _auth = AuthService();
  bool _isLogin = true;
  bool _isLoading = false;

  Future<void> _googleLogin() async {
    setState(() => _isLoading = true);
    try {
      await _auth.signInWithGoogle();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore Google: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _auth.signIn(_emailCtrl.text.trim(), _passCtrl.text.trim());
      } else {
        await _auth.signUp(_emailCtrl.text.trim(), _passCtrl.text.trim());
      }
      if (mounted) Navigator.pop(context); // Close dialog/screen on success
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLogin ? "Accedi" : "Registrati")),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(labelText: "Email"),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passCtrl,
              decoration: const InputDecoration(labelText: "Password"),
              obscureText: true,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator()
            else
              FilledButton(
                onPressed: _submit,
                child: Text(_isLogin ? "Accedi" : "Registrati"),
              ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              icon: const Icon(
                Icons.g_mobiledata,
                size: 28,
              ), // Icona Google generica o usa un asset
              label: const Text("Accedi con Google"),
              onPressed: _isLoading ? null : _googleLogin,
            ),
            TextButton(
              onPressed: () => setState(() => _isLogin = !_isLogin),
              child: Text(
                _isLogin
                    ? "Non hai un account? Registrati"
                    : "Hai già un account? Accedi",
              ),
            ),
          ],
        ),
      ),
    );
  }
}
