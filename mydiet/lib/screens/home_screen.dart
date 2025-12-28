import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // [NEW]
import '../providers/diet_provider.dart';
import '../models/active_swap.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/auth_service.dart';
import '../constants.dart';
import 'diet_view.dart';
import 'pantry_view.dart';
import 'shopping_list_view.dart';
import 'login_screen.dart';
import 'history_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late TabController _tabController;
  final AuthService _auth = AuthService();

  // [NEW] User Role State
  String _userRole = 'independent';

  final List<String> days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];

  @override
  void initState() {
    super.initState();
    int today = DateTime.now().weekday - 1;
    _tabController = TabController(
      length: 7,
      initialIndex: today < 0 ? 0 : today,
      vsync: this,
    );
    _fetchUserRole();
  }

  // [NEW] Fetch role to determine UI
  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists && mounted) {
          setState(() {
            // Default to 'independent' if field is missing
            _userRole = doc.data()?['role'] ?? 'independent';
          });
        }
      } catch (e) {
        debugPrint("Role Fetch Error: $e");
      }
    }
  }

  // --- ACTIONS ---

  Future<void> _uploadDiet(BuildContext context) async {
    final provider = context.read<DietProvider>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (!mounted) return;

    if (result != null && result.files.single.path != null) {
      try {
        await provider.uploadDiet(result.files.single.path!);
        if (!mounted) return;
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text("Dieta caricata e salvata!"),
            backgroundColor: AppColors.primary,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        String msg = provider.error ?? "Errore sconosciuto";
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _onConsume(
    BuildContext context,
    DietProvider provider,
    String name,
    String qty,
  ) {
    provider.consumeSmart(name, qty);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Hai mangiato $name! 😋"),
        duration: const Duration(seconds: 1),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  void _onEdit(
    BuildContext context,
    DietProvider provider,
    String day,
    String mealName,
    int index,
    String currentName,
    String currentQty,
  ) {
    TextEditingController nameCtrl = TextEditingController(text: currentName);
    TextEditingController qtyCtrl = TextEditingController(text: currentQty);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Modifica Piatto"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nome"),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: "Quantità"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text("Annulla"),
          ),
          FilledButton(
            onPressed: () {
              provider.updateDietMeal(
                day,
                mealName,
                index,
                nameCtrl.text,
                qtyCtrl.text,
              );
              Navigator.pop(c);
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  void _onSwap(
    BuildContext context,
    DietProvider provider,
    String swapKey,
    int cadCode,
  ) {
    String cadKey = cadCode.toString();
    final subs = provider.substitutions;

    if (subs == null || !subs.containsKey(cadKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nessuna alternativa trovata.")),
      );
      return;
    }

    var subData = subs[cadKey];
    List<dynamic> options = subData['options'] ?? [];

    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Alternative per ${subData['name']}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                separatorBuilder: (context, index) => const Divider(),
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  var opt = options[i];
                  return ListTile(
                    title: Text(opt['name']),
                    subtitle: Text(opt['qty'].toString()),
                    onTap: () {
                      provider.swapMeal(
                        swapKey,
                        ActiveSwap(
                          name: opt['name'],
                          qty: opt['qty'].toString(),
                          unit: opt['unit'] ?? "",
                        ),
                      );
                      Navigator.pop(ctx);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openTimeSettings(BuildContext context) async {
    final storage = StorageService();
    Map<String, String> times = await storage.loadMealTimes();

    TimeOfDay tColazione = _parseTime(times["colazione"]!);
    TimeOfDay tPranzo = _parseTime(times["pranzo"]!);
    TimeOfDay tCena = _parseTime(times["cena"]!);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Orari Pasti ⏰"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTimeRow(
                    context,
                    "Colazione",
                    tColazione,
                    (t) => setDialogState(() => tColazione = t),
                  ),
                  _buildTimeRow(
                    context,
                    "Pranzo",
                    tPranzo,
                    (t) => setDialogState(() => tPranzo = t),
                  ),
                  _buildTimeRow(
                    context,
                    "Cena",
                    tCena,
                    (t) => setDialogState(() => tCena = t),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annulla"),
                ),
                FilledButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final newTimes = {
                      "colazione": _formatTime(tColazione),
                      "pranzo": _formatTime(tPranzo),
                      "cena": _formatTime(tCena),
                    };
                    await storage.saveMealTimes(newTimes);
                    final notifs = NotificationService();
                    await notifs.init();
                    if (await notifs.requestPermissions()) {
                      await notifs.scheduleAllMeals();
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Orari aggiornati!")),
                        );
                    }
                  },
                  child: const Text("Salva"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTimeRow(
    BuildContext context,
    String label,
    TimeOfDay time,
    Function(TimeOfDay) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          TextButton(
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: time,
              );
              if (picked != null) onChanged(picked);
            },
            child: Text(
              "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
            ),
          ),
        ],
      ),
    );
  }

  TimeOfDay _parseTime(String s) {
    final parts = s.split(":");
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  String _formatTime(TimeOfDay t) =>
      "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  // --- UI ---

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DietProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return StreamBuilder<User?>(
      stream: _auth.authStateChanges,
      builder: (context, snapshot) {
        final user = snapshot.data;

        return Stack(
          children: [
            Scaffold(
              appBar: AppBar(
                title: const Text("MyDiet"),
                actions: [
                  if (_currentIndex == 0)
                    IconButton(
                      icon: Icon(
                        provider.isTranquilMode
                            ? Icons.spa
                            : Icons.spa_outlined,
                      ),
                      tooltip: "Modalità Relax",
                      onPressed: provider.toggleTranquilMode,
                    ),
                ],
                bottom: _currentIndex == 0
                    ? TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabs: days
                            .map(
                              (d) => Tab(text: d.substring(0, 3).toUpperCase()),
                            )
                            .toList(),
                      )
                    : null,
              ),
              drawer: _buildDrawer(context, user, provider, colorScheme),
              body: _buildBody(provider),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _currentIndex,
                onDestinationSelected: (i) => setState(() => _currentIndex = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.calendar_today),
                    label: 'Piano',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.kitchen),
                    label: 'Dispensa',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.shopping_cart),
                    label: 'Lista',
                  ),
                ],
              ),
            ),
            if (provider.isLoading)
              Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDrawer(
    BuildContext context,
    User? user,
    DietProvider provider,
    ColorScheme colors,
  ) {
    // [NEW] Check role to toggle Upload Button
    final bool canUpload = _userRole == 'independent' || _userRole == 'admin';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: const Text("MyDiet"),
            accountEmail: Text(user?.email ?? "Ospite"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: colors.primary),
            ),
            decoration: BoxDecoration(color: colors.primary),
          ),
          if (user == null)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text("Accedi / Registrati"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                );
              },
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text("Cronologia Diete"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text("Esci"),
              onTap: () {
                Navigator.pop(context);
                _auth.signOut();
              },
            ),
          ],
          const Divider(),

          // [NEW] Conditionally Render Upload
          if (canUpload)
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text("Carica Dieta PDF"),
              onTap: () => _uploadDiet(context),
            ),

          ListTile(
            leading: const Icon(Icons.access_time_filled),
            title: const Text("Imposta Orari Pasti"),
            onTap: () {
              Navigator.pop(context);
              _openTimeSettings(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text("Reset Dati Locali"),
            onTap: () {
              provider.clearData();
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBody(DietProvider provider) {
    switch (_currentIndex) {
      case 0:
        return DietView(
          tabController: _tabController,
          days: days,
          dietData: provider.dietData,
          isLoading: provider.isLoading,
          activeSwaps: provider.activeSwaps,
          substitutions: provider.substitutions,
          pantryItems: provider.pantryItems,
          isTranquilMode: provider.isTranquilMode,
          onConsume: (name, qty) => _onConsume(context, provider, name, qty),
          onEdit: (d, m, i, n, q) => _onEdit(context, provider, d, m, i, n, q),
          onSwap: (key, cad) => _onSwap(context, provider, key, cad),
        );
      case 1:
        return PantryView(
          pantryItems: provider.pantryItems,
          onAddManual: provider.addPantryItem,
          onRemove: provider.removePantryItem,
          onScanTap: () async {
            FilePickerResult? result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['jpg', 'png', 'jpeg', 'pdf'],
            );
            if (!mounted) return;
            if (result != null && result.files.single.path != null) {
              try {
                int count = await provider.scanReceipt(
                  result.files.single.path!,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Aggiunti $count prodotti!"),
                    backgroundColor: AppColors.primary,
                  ),
                );
              } catch (e) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Errore: ${provider.error ?? e}"),
                      backgroundColor: Colors.red,
                    ),
                  );
              }
            }
          },
        );
      case 2:
        return ShoppingListView(
          shoppingList: provider.shoppingList,
          dietData: provider.dietData,
          activeSwaps: provider.activeSwaps,
          pantryItems: provider.pantryItems,
          onUpdateList: provider.updateShoppingList,
          onAddToPantry: provider.addPantryItem,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
