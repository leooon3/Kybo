import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'admin_repository.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyDiet Control',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Authenticated: Check Role
        return const RoleCheckScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 400,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "MyDiet Command",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: "Password",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text("ENTER"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoleCheckScreen extends StatefulWidget {
  const RoleCheckScreen({super.key});
  @override
  State<RoleCheckScreen> createState() => _RoleCheckScreenState();
}

class _RoleCheckScreenState extends State<RoleCheckScreen> {
  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  Future<void> _checkRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final role = doc.data()?['role'];

      if (role == 'admin' || role == 'nutritionist') {
        // Access Granted -> Go to Dashboard
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const DashboardScreen()),
          );
        }
      } else {
        // Access Denied
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Access Denied: Not an Admin")),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final AdminRepository _repo = AdminRepository();
  String _filterRole = 'All'; // All, nutritionist, user

  void _showCreateUserDialog() {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    String selectedRole = 'user';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text("Create New Account"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passCtrl,
                decoration: const InputDecoration(labelText: "Password"),
              ),
              const SizedBox(height: 16),
              DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'user', child: Text("Client (User)")),
                  DropdownMenuItem(
                    value: 'nutritionist',
                    child: Text("Nutritionist"),
                  ),
                  DropdownMenuItem(value: 'admin', child: Text("Admin")),
                ],
                onChanged: (v) => setState(() => selectedRole = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            FilledButton(
              onPressed: isLoading
                  ? null
                  : () async {
                      setState(() => isLoading = true);
                      try {
                        await _repo.createUser(
                          email: emailCtrl.text.trim(),
                          password: passCtrl.text.trim(),
                          role: selectedRole,
                        );
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("User Created!")),
                        );
                      } catch (e) {
                        setState(() => isLoading = false);
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    },
              child: isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Create"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadDiet(String uid) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // Critical for Web
    );

    if (result != null) {
      try {
        await _repo.uploadDietForUser(uid, result.files.single);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Diet Injected Successfully!")),
        );
      } catch (e) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Upload Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("MyDiet God Mode ⚡"),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserDialog,
        icon: const Icon(Icons.add),
        label: const Text("Add User"),
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text(
                  "Filter: ",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 10),
                ToggleButtons(
                  isSelected: [
                    _filterRole == 'All',
                    _filterRole == 'nutritionist',
                    _filterRole == 'user',
                  ],
                  onPressed: (idx) {
                    setState(() {
                      if (idx == 0) _filterRole = 'All';
                      if (idx == 1) _filterRole = 'nutritionist';
                      if (idx == 2) _filterRole = 'user';
                    });
                  },
                  children: const [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("All"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("Nutritionists"),
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text("Clients"),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _repo.getAllUsers(),
              builder: (context, snapshot) {
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());

                var users = snapshot.data!;
                if (_filterRole != 'All') {
                  users = users.where((u) => u['role'] == _filterRole).toList();
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (ctx, i) {
                    final user = users[i];
                    final bool isActive = user['is_active'] ?? true;
                    final String role = user['role'] ?? 'user';
                    final String email = user['email'] ?? 'No Email';
                    final String uid = user['uid'];

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive ? Colors.green : Colors.red,
                          child: Icon(
                            role == 'admin'
                                ? Icons.security
                                : (role == 'nutritionist'
                                      ? Icons.medical_services
                                      : Icons.person),
                            color: Colors.white,
                          ),
                        ),
                        title: Text(
                          email,
                          style: TextStyle(
                            decoration: isActive
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text("Role: $role | UID: $uid"),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (role == 'user' || role == 'independent')
                              IconButton(
                                icon: const Icon(
                                  Icons.upload_file,
                                  color: Colors.blue,
                                ),
                                tooltip: "Inject Diet",
                                onPressed: () => _uploadDiet(uid),
                              ),
                            IconButton(
                              icon: Icon(
                                isActive ? Icons.block : Icons.check_circle,
                                color: isActive ? Colors.red : Colors.green,
                              ),
                              tooltip: isActive ? "Ban User" : "Unban User",
                              onPressed: () =>
                                  _repo.toggleUserStatus(uid, isActive),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
