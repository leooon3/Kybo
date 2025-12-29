import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../admin_repository.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final AdminRepository _repo = AdminRepository();
  bool _isLoading = false;

  // Filtri UI
  String _searchQuery = "";
  String _roleFilter = "all";
  final TextEditingController _searchCtrl = TextEditingController();

  // Dati Utente Loggato
  String _currentUserId = '';
  String _currentUserRole = '';
  bool _isDataLoaded = false;

  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }

  Future<void> _checkCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (mounted && doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _currentUserId = user.uid;
          _currentUserRole = data['role'] ?? 'user';
          _isDataLoaded = true;
        });
      }
    }
  }

  Stream<QuerySnapshot> _getUsersStream() {
    final usersRef = FirebaseFirestore.instance.collection('users');

    if (_currentUserRole == 'admin') {
      // Admin vede tutto
      return usersRef.snapshots();
    } else if (_currentUserRole == 'nutritionist') {
      // Nutrizionista vede solo i suoi creati
      return usersRef
          .where('created_by', isEqualTo: _currentUserId)
          .snapshots();
    } else {
      return const Stream.empty();
    }
  }

  // --- ACTIONS ---

  Future<void> _syncUsers() async {
    setState(() => _isLoading = true);
    try {
      String msg = await _repo.syncUsers();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.blue),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sync Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteUser(String uid) async {
    if (!mounted) return;
    bool confirm =
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text("Elimina Utente"),
            content: const Text("Sei sicuro? L'azione è irreversibile."),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text("Annulla"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(c, true),
                child: const Text("Elimina"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      setState(() => _isLoading = true);
      try {
        await _repo.deleteUser(uid);
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Utente eliminato.")));
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text("Errore: $e")));
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadDiet(String targetUid) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _isLoading = true);
      try {
        await _repo.uploadDietForUser(targetUid, result.files.single);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Dieta caricata!"),
              backgroundColor: Colors.green,
            ),
          );
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Errore upload: $e"),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _uploadParser(String targetUid) async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );
    if (result != null && result.files.single.bytes != null) {
      setState(() => _isLoading = true);
      try {
        await _repo.uploadParserConfig(targetUid, result.files.single);
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Parser caricato!"),
              backgroundColor: Colors.green,
            ),
          );
      } catch (e) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Errore parser: $e"),
              backgroundColor: Colors.red,
            ),
          );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showCreateUserDialog() async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final surnameCtrl = TextEditingController();
    String role = 'user';

    List<DropdownMenuItem<String>> allowedRoles = [
      const DropdownMenuItem(value: 'user', child: Text("Cliente")),
    ];

    if (_currentUserRole == 'admin') {
      allowedRoles.addAll([
        const DropdownMenuItem(
          value: 'nutritionist',
          child: Text("Nutrizionista"),
        ),
        const DropdownMenuItem(
          value: 'independent',
          child: Text("Indipendente"),
        ),
        const DropdownMenuItem(value: 'admin', child: Text("Admin")),
      ]);
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Nuovo Utente"),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(labelText: "Nome"),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: TextField(
                          controller: surnameCtrl,
                          decoration: const InputDecoration(
                            labelText: "Cognome",
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.email),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passCtrl,
                    decoration: const InputDecoration(
                      labelText: "Password Temp",
                      prefixIcon: Icon(Icons.key),
                    ),
                  ),
                  const SizedBox(height: 24),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: "Ruolo"),
                    items: allowedRoles,
                    onChanged: (v) => setDialogState(() => role = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annulla"),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                setState(() => _isLoading = true);
                try {
                  await _repo.createUser(
                    email: emailCtrl.text,
                    password: passCtrl.text,
                    role: role,
                    firstName: nameCtrl.text,
                    lastName: surnameCtrl.text,
                  );
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Utente creato!")),
                    );
                } catch (e) {
                  if (mounted)
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text("Errore: $e")));
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("Crea"),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.purple;
      case 'nutritionist':
        return Colors.blue;
      case 'independent':
        return Colors.orange;
      default:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isDataLoaded) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        // --- TOP TOOLBAR ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    hintText: "Cerca utente...",
                    prefixIcon: Icon(Icons.search),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onChanged: (val) =>
                      setState(() => _searchQuery = val.toLowerCase()),
                ),
              ),

              // [MODIFICA] Filtro ruolo visibile SOLO per Admin
              if (_currentUserRole == 'admin') ...[
                const VerticalDivider(),
                DropdownButton<String>(
                  value: _roleFilter,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text("Tutti i Ruoli"),
                    ),
                    DropdownMenuItem(value: 'user', child: Text("Clienti")),
                    DropdownMenuItem(
                      value: 'nutritionist',
                      child: Text("Nutrizionisti"),
                    ),
                    DropdownMenuItem(
                      value: 'independent',
                      child: Text("Indipendenti"),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text("Admin")),
                  ],
                  onChanged: (val) => setState(() => _roleFilter = val!),
                ),
              ],

              const Spacer(),
              // Actions
              IconButton(
                icon: const Icon(Icons.sync, color: Colors.blue),
                tooltip: "Sync DB",
                onPressed: _isLoading ? null : _syncUsers,
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _isLoading ? null : _showCreateUserDialog,
                icon: const Icon(Icons.add),
                label: const Text("NUOVO UTENTE"),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),
        if (_isLoading) const LinearProgressIndicator(),
        const SizedBox(height: 20),

        // --- USER GRID ---
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _getUsersStream(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Text('Err: ${snapshot.error}');
              if (!snapshot.hasData)
                return const Center(child: CircularProgressIndicator());

              var docs = snapshot.data!.docs;

              final filteredUsers = docs.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = (data['role'] ?? 'user').toString().toLowerCase();
                final name =
                    "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}"
                        .toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();

                // 1. Filtro Ruolo (Solo se Admin lo sta usando)
                if (_currentUserRole == 'admin' &&
                    _roleFilter != 'all' &&
                    role != _roleFilter)
                  return false;

                // 2. Filtro Ricerca
                if (_searchQuery.isNotEmpty) {
                  return name.contains(_searchQuery) ||
                      email.contains(_searchQuery);
                }

                return true;
              }).toList();

              // Ordinamento
              filteredUsers.sort((a, b) {
                Timestamp? tA =
                    (a.data() as Map<String, dynamic>)['created_at'];
                Timestamp? tB =
                    (b.data() as Map<String, dynamic>)['created_at'];
                if (tA == null) return 1;
                if (tB == null) return -1;
                return tB.compareTo(tA);
              });

              if (filteredUsers.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_off,
                        size: 48,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _currentUserRole == 'nutritionist'
                            ? "Non hai ancora creato nessun cliente."
                            : "Nessun utente trovato.",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              }

              return GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 400,
                  mainAxisExtent: 230,
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                ),
                itemCount: filteredUsers.length,
                itemBuilder: (context, index) {
                  final data =
                      filteredUsers[index].data() as Map<String, dynamic>;
                  final role = data['role'] ?? 'user';
                  final name =
                      "${data['first_name'] ?? ''} ${data['last_name'] ?? ''}";
                  final date = data['created_at'] != null
                      ? DateFormat(
                          'dd MMM yyyy',
                        ).format((data['created_at'] as Timestamp).toDate())
                      : '-';

                  bool showParser = role == 'nutritionist';
                  bool showDiet = role == 'user' || role == 'independent';
                  bool canDelete =
                      _currentUserRole == 'admin' || role == 'user';

                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: _getRoleColor(
                                  role,
                                ).withOpacity(0.2),
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : "?",
                                  style: TextStyle(
                                    color: _getRoleColor(role),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      data['email'] ?? 'No Email',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _getRoleColor(role).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  role.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: _getRoleColor(role),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          const Divider(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (showDiet)
                                IconButton(
                                  icon: const Icon(
                                    Icons.upload_file,
                                    color: Colors.blueGrey,
                                  ),
                                  tooltip: "Carica Dieta",
                                  onPressed: () => _uploadDiet(data['uid']),
                                ),

                              if (showParser)
                                IconButton(
                                  icon: const Icon(
                                    Icons.settings_applications,
                                    color: Colors.orange,
                                  ),
                                  tooltip: "Configura Parser",
                                  onPressed: () => _uploadParser(data['uid']),
                                ),

                              const SizedBox(width: 8),

                              if (canDelete)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  tooltip: "Elimina",
                                  onPressed: () => _deleteUser(data['uid']),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              "Creato il: $date",
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey[400],
                              ),
                            ),
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
    );
  }
}
