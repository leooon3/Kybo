import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// --- CONFIGURAZIONE SERVER (Inserisci il TUO IP qui!) ---
const String serverUrl = 'http://192.168.1.53:8000';

void main() {
  runApp(const DietApp());
}

// --- MODELLI DATI ---
class PantryItem {
  String name;
  double quantity;
  String unit; // "g" o "pz"

  PantryItem({required this.name, required this.quantity, required this.unit});

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit': unit,
  };
  factory PantryItem.fromJson(Map<String, dynamic> json) => PantryItem(
    name: json['name'],
    quantity: json['quantity'],
    unit: json['unit'],
  );
}

class ActiveSwap {
  String name;
  String qty;
  ActiveSwap({required this.name, required this.qty});

  Map<String, dynamic> toJson() => {'name': name, 'qty': qty};
  factory ActiveSwap.fromJson(Map<String, dynamic> json) =>
      ActiveSwap(name: json['name'], qty: json['qty']);
}

// --- LISTE KEYWORDS ---
const Set<String> fruitKeywords = {
  'mela',
  'mele',
  'pera',
  'pere',
  'banana',
  'banane',
  'arance',
  'arancia',
  'ananas',
  'kiwi',
  'pesche',
  'albicocche',
  'fragole',
  'ciliegie',
  'prugne',
  'fichi',
  'uva',
  'caco',
  'cachi',
};

const Set<String> veggieKeywords = {
  'zucchine',
  'melanzane',
  'pomodori',
  'cetrioli',
  'insalata',
  'rucola',
  'bieta',
  'spinaci',
  'carote',
  'finocchi',
  'verza',
  'cavolfiore',
  'broccoli',
  'minestrone',
  'verdure',
  'fagiolini',
  'cicoria',
  'radicchio',
  'indivia',
  'zucca',
  'asparagi',
  'peperoni',
  'sedano',
  'lattuga',
  'funghi',
};

class DietApp extends StatelessWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // Verde Foresta
          secondary: const Color(0xFFE65100), // Arancione Accento
          surface: const Color(0xFFF5F7F6), // Sfondo Grigio-Perla
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1B5E20),
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
          iconTheme: IconThemeData(color: Color(0xFF1B5E20)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? dietData;
  Map<String, dynamic>? substitutions;
  Map<String, ActiveSwap> activeSwaps = {};
  List<PantryItem> pantryItems = [];

  bool isLoading = true;
  bool isUploading = false;
  bool isTranquilMode = false;

  int _currentIndex = 0;
  late TabController _tabController;
  final List<String> days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];

  final TextEditingController _pantryNameController = TextEditingController();
  final TextEditingController _pantryQtyController = TextEditingController();
  String _manualUnit = 'g';

  @override
  void initState() {
    super.initState();
    int todayIndex = DateTime.now().weekday - 1;
    if (todayIndex < 0) todayIndex = 0;
    _tabController = TabController(
      length: days.length,
      initialIndex: todayIndex,
      vsync: this,
    );
    _loadLocalData();
  }

  // --- SALVATAGGIO DATI ---
  Future<void> _loadLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    String? dietJson = prefs.getString('dietData');
    if (dietJson != null) {
      final data = json.decode(dietJson);
      setState(() {
        dietData = data['plan'];
        substitutions = data['substitutions'];
      });
    } else {
      // Fallback: Carica da assets se non c'è nulla in memoria
      _loadAssetDiet();
    }

    String? pantryJson = prefs.getString('pantryItems');
    if (pantryJson != null) {
      List<dynamic> decoded = json.decode(pantryJson);
      setState(
        () => pantryItems = decoded
            .map((item) => PantryItem.fromJson(item))
            .toList(),
      );
    }

    String? swapsJson = prefs.getString('activeSwaps');
    if (swapsJson != null) {
      Map<String, dynamic> decoded = json.decode(swapsJson);
      setState(
        () => activeSwaps = decoded.map(
          (key, value) => MapEntry(key, ActiveSwap.fromJson(value)),
        ),
      );
    }
    setState(() => isLoading = false);
  }

  Future<void> _loadAssetDiet() async {
    try {
      final String response = await rootBundle.loadString('assets/dieta.json');
      final data = json.decode(response);
      setState(() {
        dietData = data['plan'];
        substitutions = data['substitutions'];
      });
    } catch (e) {
      debugPrint("Nessun asset dieta trovato: $e");
    }
  }

  Future<void> _saveLocalData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(
      'pantryItems',
      json.encode(pantryItems.map((e) => e.toJson()).toList()),
    );
    prefs.setString(
      'activeSwaps',
      json.encode(
        activeSwaps.map((key, value) => MapEntry(key, value.toJson())),
      ),
    );
    if (dietData != null) {
      prefs.setString(
        'dietData',
        json.encode({'plan': dietData, 'substitutions': substitutions}),
      );
    }
  }

  // --- FUNZIONI SERVER (QUELLE CHE MANCAVANO!) ---

  // 1. Upload Dieta
  Future<void> _uploadDietPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null) {
      setState(() => isUploading = true);
      File file = File(result.files.single.path!);
      try {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/upload-diet'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));
          setState(() {
            dietData = data['plan'];
            substitutions = data['substitutions'];
            isUploading = false;
          });
          _saveLocalData();
          Navigator.pop(context); // Chiude drawer
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Dieta Aggiornata!"),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          throw Exception("Errore Server: ${response.statusCode}");
        }
      } catch (e) {
        setState(() => isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Errore: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 2. Scan Scontrino
  Future<void> _scanReceiptWithServer() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'png', 'pdf'],
    );
    if (result != null) {
      setState(() => isUploading = true);
      File file = File(result.files.single.path!);
      try {
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('$serverUrl/scan-receipt'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final List<dynamic> importedItems = json.decode(
            utf8.decode(response.bodyBytes),
          );
          setState(() => isUploading = false);

          int added = 0;
          if (importedItems.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Nessun cibo trovato."),
                backgroundColor: Colors.orange,
              ),
            );
            return;
          }

          for (var item in importedItems) {
            String name = item['name'];
            if (name.toLowerCase().contains("filetti")) {
              String? s = await _showFilettiDialog();
              if (s != null)
                name = s;
              else
                continue;
            }
            var result = await _showQuantityDialog(name);
            if (result != null && result['qty'] > 0) {
              _addOrUpdatePantry(name, result['qty'], result['unit']);
              added++;
            }
          }
          if (added > 0)
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Aggiunti $added prodotti!"),
                backgroundColor: Colors.green,
              ),
            );
        } else {
          throw Exception("Errore Server: ${response.statusCode}");
        }
      } catch (e) {
        setState(() => isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Errore Scan: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- LOGICHE HELPER ---
  bool _isFruit(String name) {
    String lower = name.toLowerCase();
    if (lower.contains("melanzan")) return false;
    for (var k in fruitKeywords) if (lower.contains(k)) return true;
    return false;
  }

  bool _isVeggie(String name) {
    String lower = name.toLowerCase();
    for (var k in veggieKeywords) if (lower.contains(k)) return true;
    return false;
  }

  String _getDisplayQuantity(String name, String originalQty) {
    if (isTranquilMode) {
      if (_isFruit(name)) return "1 frutto";
      if (_isVeggie(name)) return "A volontà";
    }
    return originalQty;
  }

  double _parseDietQuantity(String qtyString) {
    RegExp regExp = RegExp(r'(\d+(?:[.,]\d+)?)');
    var match = regExp.firstMatch(qtyString);
    if (match != null)
      return double.parse(match.group(1)!.replaceAll(',', '.'));
    return 0.0;
  }

  // --- GESTIONE DISPENSA ---
  void _addOrUpdatePantry(String name, double qty, String unit) {
    int existingIndex = pantryItems.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && p.unit == unit,
    );
    if (existingIndex != -1) {
      pantryItems[existingIndex].quantity += qty;
    } else {
      pantryItems.add(PantryItem(name: name, quantity: qty, unit: unit));
    }
    _saveLocalData();
  }

  void _addToPantryManual() {
    if (_pantryNameController.text.isNotEmpty) {
      double qty =
          double.tryParse(_pantryQtyController.text.replaceAll(',', '.')) ??
          1.0;
      _addOrUpdatePantry(_pantryNameController.text.trim(), qty, _manualUnit);
      _pantryNameController.clear();
      _pantryQtyController.clear();
      FocusScope.of(context).unfocus();
      setState(() {});
    }
  }

  void _consumeFood(String name, String dietQtyString) {
    int idx = pantryItems.indexWhere(
      (p) =>
          name.toLowerCase().contains(p.name.toLowerCase()) ||
          p.name.toLowerCase().contains(name.toLowerCase()),
    );
    if (idx == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Non hai $name!"),
          backgroundColor: Colors.red[100],
        ),
      );
      return;
    }
    PantryItem item = pantryItems[idx];
    double qtyToEat = 0.0;
    if (item.unit == 'g') {
      qtyToEat = _parseDietQuantity(dietQtyString);
      if (qtyToEat == 0) qtyToEat = 100; // Fallback se parsing fallisce
    } else {
      qtyToEat = 1.0;
    }

    setState(() {
      item.quantity -= qtyToEat;
      if (item.quantity <= 0.1) {
        pantryItems.removeAt(idx);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Finito! 🗑️"),
            backgroundColor: Colors.orange,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Gnam! Rimasti ${item.quantity.toInt()} ${item.unit}",
            ),
            backgroundColor: Colors.green[700],
          ),
        );
      }
      _saveLocalData();
    });
  }

  bool _isInPantry(String name) {
    for (var item in pantryItems) {
      if (name.toLowerCase().contains(item.name.toLowerCase()) ||
          item.name.toLowerCase().contains(name.toLowerCase()))
        return true;
    }
    return false;
  }

  // --- DIALOGHI ---
  Future<String?> _showFilettiDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text("Filetti di cosa?"),
        backgroundColor: Colors.white,
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, "Petto di pollo"),
            child: const Text("🐓 Pollo"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, "Platessa"),
            child: const Text("🐟 Pesce"),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, "Manzo magro"),
            child: const Text("🥩 Manzo"),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>?> _showQuantityDialog(String itemName) {
    TextEditingController q = TextEditingController();
    String u = (_isFruit(itemName) || _isVeggie(itemName)) ? 'pz' : 'g';
    return showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, st) => AlertDialog(
          backgroundColor: Colors.white,
          title: Text("Aggiungi $itemName"),
          content: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: q,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: "0"),
                ),
              ),
              SizedBox(width: 10),
              DropdownButton<String>(
                value: u,
                items: const [
                  DropdownMenuItem(value: 'g', child: Text("g")),
                  DropdownMenuItem(value: 'pz', child: Text("pz")),
                ],
                onChanged: (v) => st(() => u = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("Salta"),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(c, {
                'qty': double.tryParse(q.text) ?? 0.0,
                'unit': u,
              }),
              child: const Text("Ok"),
            ),
          ],
        ),
      ),
    );
  }

  void _editMealItem(
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
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text("Modifica"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: "Nome"),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              decoration: const InputDecoration(labelText: "Quantità"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annulla"),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
            onPressed: () {
              setState(() {
                dietData![day][mealName][index]['name'] = nameCtrl.text;
                dietData![day][mealName][index]['qty'] = qtyCtrl.text;
              });
              _saveLocalData();
              Navigator.pop(context);
            },
            child: const Text("Salva"),
          ),
        ],
      ),
    );
  }

  // --- LISTA SPESA ---
  void _generateShoppingList() {
    showDialog(
      context: context,
      builder: (context) {
        int d = 3;
        return StatefulBuilder(
          builder: (context, st) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text("Lista Spesa 🛒"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Per $d giorni"),
                Slider(
                  value: d.toDouble(),
                  min: 1,
                  max: 7,
                  divisions: 6,
                  activeColor: Colors.green,
                  onChanged: (v) => st(() => d = v.toInt()),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annulla"),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
                onPressed: () {
                  Navigator.pop(context);
                  _showShoppingResults(d);
                },
                child: const Text("Calcola"),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showShoppingResults(int daysCount) {
    Map<String, double> needed = {};
    int startDay = DateTime.now().weekday - 1;
    for (int i = 0; i < daysCount; i++) {
      var dayPlan = dietData![days[(startDay + i) % 7]];
      if (dayPlan != null)
        dayPlan.forEach((_, foods) {
          for (var f in foods) {
            double q = _parseDietQuantity(f['qty']);
            if (q > 0)
              needed[f['name'].trim().toLowerCase()] =
                  (needed[f['name'].trim().toLowerCase()] ?? 0) + q;
          }
        });
    }

    Map<String, double> toBuy = {};
    needed.forEach((name, qty) {
      double inPantry = 0;
      try {
        var item = pantryItems.firstWhere(
          (p) =>
              p.name.toLowerCase().contains(name) ||
              name.contains(p.name.toLowerCase()),
        );
        inPantry = (item.unit == 'pz') ? item.quantity * 150 : item.quantity;
      } catch (e) {
        inPantry = 0;
      }
      if (inPantry < qty) toBuy[name] = qty - inPantry;
    });

    Map<String, bool> checks = {for (var k in toBuy.keys) k: false};

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (context) => StatefulBuilder(
        builder: (context, st) => Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                "Lista Spesa",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: toBuy.isEmpty
                    ? const Center(child: Text("Tutto ok! 🎉"))
                    : ListView(
                        children: toBuy.entries
                            .map(
                              (e) => CheckboxListTile(
                                title: Text(e.key.toUpperCase()),
                                subtitle: Text("Mancano: ${e.value.toInt()}g"),
                                value: checks[e.key],
                                activeColor: Colors.green,
                                onChanged: (v) => st(() => checks[e.key] = v!),
                              ),
                            )
                            .toList(),
                      ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green[700],
                ),
                icon: const Icon(Icons.shopping_cart_checkout),
                label: const Text("COMPRA SELEZIONATI"),
                onPressed: () {
                  checkedItemsToPantry(checks, toBuy);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void checkedItemsToPantry(
    Map<String, bool> checks,
    Map<String, double> list,
  ) {
    int c = 0;
    checks.forEach((name, checked) {
      if (checked) {
        _addOrUpdatePantry(name, list[name]!, 'g');
        c++;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Aggiunti $c prodotti!"),
        backgroundColor: Colors.green,
      ),
    );
  }

  // --- UI PRINCIPALE ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(
        backgroundColor: Colors.white,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const UserAccountsDrawerHeader(
              accountName: Text("NutriScan"),
              accountEmail: Text("Gestione Dieta"),
              currentAccountPicture: CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(Icons.local_dining, color: Colors.green),
              ),
              decoration: BoxDecoration(color: Color(0xFF2E7D32)),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text("Carica Nuova Dieta PDF"),
              onTap: _uploadDietPdf,
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text("Resetta Dati"),
              onTap: () async {
                final p = await SharedPreferences.getInstance();
                await p.clear();
                setState(() {
                  dietData = null;
                  pantryItems = [];
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(_currentIndex == 0 ? 'MyDiet' : 'Dispensa'),
            floating: true,
            pinned: true,
            snap: false,
            actions: [
              if (_currentIndex == 0 && dietData != null)
                IconButton(
                  icon: const Icon(
                    Icons.shopping_cart,
                    color: Color(0xFFE65100),
                  ),
                  onPressed: _generateShoppingList,
                ),
              if (_currentIndex == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Transform.scale(
                    scale: 0.9,
                    child: Switch(
                      value: isTranquilMode,
                      onChanged: (val) => setState(() => isTranquilMode = val),
                      activeColor: Colors.green,
                      thumbIcon: MaterialStateProperty.resolveWith<Icon?>(
                        (states) => states.contains(MaterialState.selected)
                            ? const Icon(Icons.spa, color: Colors.white)
                            : const Icon(Icons.scale, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
            ],
            bottom: _currentIndex == 0
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.green[800],
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          color: const Color(0xFF2E7D32),
                        ),
                        tabs: days
                            .map(
                              (day) => Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(
                                    color: Colors.green.withOpacity(0.2),
                                  ),
                                ),
                                child: Tab(
                                  text: day.substring(0, 3).toUpperCase(),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  )
                : null,
          ),
        ],
        body: _currentIndex == 0 ? _buildDietView() : _buildPantryView(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: Colors.white,
        elevation: 10,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined),
            selectedIcon: Icon(Icons.calendar_today, color: Colors.green),
            label: 'Piano',
          ),
          NavigationDestination(
            icon: Icon(Icons.kitchen_outlined),
            selectedIcon: Icon(Icons.kitchen, color: Colors.green),
            label: 'Frigo',
          ),
        ],
      ),
    );
  }

  // ... (Codice UI Dieta e Dispensa rimasto uguale alla V "Fluid", ma integrato con le chiamate _scanReceiptWithServer e _uploadDietPdf)
  // Per brevità, includo qui le parti cruciali che collegano tutto.

  Widget _buildDietView() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (dietData == null)
      return const Center(
        child: Text("Nessuna dieta. Caricala dal menu laterale!"),
      );
    return TabBarView(
      controller: _tabController,
      physics: const BouncingScrollPhysics(),
      children: days.map((day) => _buildDayList(day)).toList(),
    );
  }

  Widget _buildDayList(String day) {
    final dayPlan = dietData![day];
    if (dayPlan == null) return const Center(child: Text("Giorno Libero!"));
    final mealOrder = [
      "Colazione",
      "Seconda Colazione",
      "Pranzo",
      "Merenda",
      "Cena",
      "Spuntino Serale",
      "Nell'Arco Della Giornata",
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const BouncingScrollPhysics(),
      children: mealOrder.map((mealName) {
        final foods = dayPlan[mealName];
        if (foods == null || foods.isEmpty) return const SizedBox.shrink();
        return _buildMealCard(day, mealName, foods);
      }).toList(),
    );
  }

  Widget _buildMealCard(String day, String mealName, List<dynamic> foods) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              mealName.toUpperCase(),
              style: TextStyle(
                color: Colors.green[800],
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B5E20).withOpacity(0.05),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: foods
                  .asMap()
                  .entries
                  .map(
                    (e) => _buildFoodRow(
                      day,
                      mealName,
                      e.key,
                      e.value,
                      e.key == foods.length - 1,
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFoodRow(
    String day,
    String mealName,
    int index,
    dynamic food,
    bool isLast,
  ) {
    String swapKey = "${day}_${mealName}_$index";
    String currentName = activeSwaps[swapKey]?.name ?? food['name'];
    String currentQty = activeSwaps[swapKey]?.qty ?? food['qty'];
    String? cad = food['cad_code'];
    bool hasSubstitutions =
        cad != null && substitutions != null && substitutions!.containsKey(cad);
    bool inFrigo = _isInPantry(currentName);
    String displayQty = _getDisplayQuantity(currentName, currentQty);

    return InkWell(
      onTap: inFrigo ? () => _consumeFood(currentName, currentQty) : null,
      onLongPress: () =>
          _editMealItem(day, mealName, index, currentName, currentQty),
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(24))
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: inFrigo ? Colors.green : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: inFrigo ? Colors.green : Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: inFrigo
                      ? const Icon(Icons.check, size: 18, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: inFrigo ? Colors.green[900] : Colors.black87,
                          decoration: inFrigo
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      if (displayQty.isNotEmpty && displayQty != "N/A")
                        Text(
                          displayQty,
                          style: TextStyle(
                            color: Colors.green[600],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasSubstitutions)
                  IconButton(
                    icon: Icon(
                      Icons.swap_horiz,
                      color: activeSwaps.containsKey(swapKey)
                          ? Colors.purple
                          : Colors.orange[300],
                    ),
                    onPressed: () => _showSubstitutions(
                      day,
                      mealName,
                      index,
                      currentName,
                      cad!,
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16, color: Colors.grey),
                  onPressed: () => _editMealItem(
                    day,
                    mealName,
                    index,
                    currentName,
                    currentQty,
                  ),
                ),
              ],
            ),
          ),
          if (!isLast)
            Divider(
              height: 1,
              indent: 60,
              endIndent: 20,
              color: Colors.grey[100],
            ),
        ],
      ),
    );
  }

  void _showSubstitutions(
    String day,
    String mealName,
    int index,
    String currentName,
    String cadCode,
  ) {
    var subData = substitutions![cadCode];
    List<dynamic> options = subData['options'] ?? [];
    String info = subData['info'] ?? "";
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (_, scroll) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Alternative",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  if (info.isNotEmpty)
                    IconButton.filledTonal(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => showDialog(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: Colors.white,
                          title: const Text("Info"),
                          content: Text(info),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.separated(
                  controller: scroll,
                  physics: const BouncingScrollPhysics(),
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemCount: options.length,
                  itemBuilder: (context, i) {
                    var opt = options[i];
                    String optName = opt['name'];
                    String optQty = opt['qty'];
                    bool isSelected = optName == currentName;
                    return InkWell(
                      onTap: () {
                        setState(
                          () => activeSwaps["${day}_${mealName}_$index"] =
                              ActiveSwap(name: optName, qty: optQty),
                        );
                        _saveLocalData();
                        Navigator.pop(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.green[50] : Colors.white,
                          border: Border.all(
                            color: isSelected
                                ? Colors.green
                                : Colors.grey[200]!,
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: isSelected
                                  ? Colors.green
                                  : Colors.grey[300],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                optName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              optQty != "N/A" ? optQty : "",
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPantryView() {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanReceiptWithServer,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text("Scan Scontrino"),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _pantryNameController,
                    decoration: const InputDecoration(
                      hintText: "Cibo",
                      prefixIcon: Icon(Icons.edit_note),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _pantryQtyController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(hintText: "0"),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButton<String>(
                    value: _manualUnit,
                    underline: Container(),
                    icon: const Icon(
                      Icons.arrow_drop_down,
                      color: Colors.green,
                    ),
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text("g")),
                      DropdownMenuItem(value: 'pz', child: Text("pz")),
                    ],
                    onChanged: (val) => setState(() => _manualUnit = val!),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _addToPantryManual,
                  icon: const Icon(Icons.add),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: pantryItems.isEmpty
                ? Center(
                    child: Text(
                      "Vuoto",
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    physics: const BouncingScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 1.3,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: pantryItems.length,
                    itemBuilder: (context, index) {
                      final item = pantryItems[index];
                      bool isLow = item.quantity < 2;
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.grey[100]!),
                        ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: 8,
                              top: 8,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() => pantryItems.removeAt(index));
                                  _saveLocalData();
                                },
                                child: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: Colors.grey[300],
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isLow
                                        ? Colors.orange[50]
                                        : Colors.green[50],
                                    radius: 20,
                                    child: Text(
                                      item.name[0].toUpperCase(),
                                      style: TextStyle(
                                        color: isLow
                                            ? Colors.orange
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "${item.quantity.toInt()} ${item.unit}",
                                    style: TextStyle(
                                      color: isLow
                                          ? Colors.orange
                                          : Colors.green[700],
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
