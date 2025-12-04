import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

void main() {
  runApp(const DietApp());
}

class PantryItem {
  String name;
  double quantity;
  String unit; // "g" o "pz"
  PantryItem({required this.name, required this.quantity, required this.unit});
}

class ActiveSwap {
  String name;
  String qty;
  ActiveSwap({required this.name, required this.qty});
}

// KEYWORDS FRUTTA
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

// KEYWORDS VERDURA
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
      title: 'MyDiet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32), // Verde Foresta
          secondary: const Color(0xFFE65100), // Arancione Accento
          surface: const Color(0xFFF5F7F6), // Sfondo Grigio-Perla
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7F6),
        // Tipografia e Stili Globali
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
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
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

  bool isLoading = true;
  bool isTranquilMode = false;

  List<PantryItem> pantryItems = [];
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
  String _manualUnit = 'g'; // Default unit manuale

  @override
  void initState() {
    super.initState();
    int todayIndex = DateTime.now().weekday - 1;
    _tabController = TabController(
      length: days.length,
      initialIndex: todayIndex,
      vsync: this,
    );
    loadDietData();
  }

  Future<void> loadDietData() async {
    try {
      final String response = await rootBundle.loadString('assets/dieta.json');
      final data = json.decode(response);
      setState(() {
        dietData = data['plan'];
        substitutions = data['substitutions'];
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

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

  Future<void> _importGroceryList() async {
    try {
      final String response = await rootBundle.loadString(
        'assets/spesa_importata.json',
      );
      final List<dynamic> importedItems = json.decode(response);

      int added = 0;
      for (var item in importedItems) {
        String name = item['name'];
        if (name.toLowerCase().contains("filetti")) {
          String? specificName = await _showFilettiDialog();
          if (specificName != null)
            name = specificName;
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
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Nessun scontrino trovato."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _showFilettiDialog() {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => SimpleDialog(
        title: const Text("Filetti di cosa?"),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
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
    TextEditingController qtyCtrl = TextEditingController();
    String selectedUnit = (_isFruit(itemName) || _isVeggie(itemName))
        ? 'pz'
        : 'g';

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          title: Text(
            "Aggiungi $itemName",
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Quanto ne hai comprato?",
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyCtrl,
                      keyboardType: TextInputType.number,
                      autofocus: true,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(hintText: "0"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: selectedUnit,
                    underline: Container(),
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'g', child: Text("Grammi")),
                      DropdownMenuItem(value: 'pz', child: Text("Pezzi")),
                    ],
                    onChanged: (val) => setState(() => selectedUnit = val!),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text("Salta", style: TextStyle(color: Colors.grey)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.green[700]),
              onPressed: () => Navigator.pop(context, {
                'qty': double.tryParse(qtyCtrl.text) ?? 0.0,
                'unit': selectedUnit,
              }),
              child: const Text("Conferma"),
            ),
          ],
        ),
      ),
    );
  }

  void _addOrUpdatePantry(String name, double qty, String unit) {
    int existingIndex = pantryItems.indexWhere(
      (p) => p.name.toLowerCase() == name.toLowerCase() && p.unit == unit,
    );
    if (existingIndex != -1) {
      pantryItems[existingIndex].quantity += qty;
    } else {
      pantryItems.add(PantryItem(name: name, quantity: qty, unit: unit));
    }
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
    int foundIndex = -1;
    for (int i = 0; i < pantryItems.length; i++) {
      if (name.toLowerCase().contains(pantryItems[i].name.toLowerCase()) ||
          pantryItems[i].name.toLowerCase().contains(name.toLowerCase())) {
        foundIndex = i;
        break;
      }
    }

    if (foundIndex == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Non hai $name!"),
          backgroundColor: Colors.red[100],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    PantryItem item = pantryItems[foundIndex];
    double qtyToEat = 0.0;

    if (item.unit == 'g') {
      RegExp regExp = RegExp(r'(\d+(?:[.,]\d+)?)');
      var match = regExp.firstMatch(dietQtyString);
      if (match != null)
        qtyToEat = double.parse(match.group(1)!.replaceAll(',', '.'));
    } else if (item.unit == 'pz') {
      qtyToEat = 1.0;
    }

    setState(() {
      item.quantity -= qtyToEat;
      if (item.quantity <= 0.1) {
        pantryItems.removeAt(foundIndex);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Finito $name! 🗑️"),
            backgroundColor: Colors.orange,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "Gnam! Rimasti ${item.quantity.toInt()} ${item.unit}",
            ),
            backgroundColor: Colors.green[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });
  }

  bool _isInPantry(String name) {
    for (var item in pantryItems) {
      if (name.toLowerCase().contains(item.name.toLowerCase()) ||
          item.name.toLowerCase().contains(name.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            title: Text(_currentIndex == 0 ? 'MyDiet' : 'Dispensa'),
            floating: true,
            pinned: true,
            snap: false,
            actions: [
              if (_currentIndex == 0)
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => isTranquilMode = !isTranquilMode),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isTranquilMode
                            ? Colors.green[100]
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isTranquilMode ? Icons.spa : Icons.scale,
                            size: 18,
                            color: isTranquilMode
                                ? Colors.green[800]
                                : Colors.grey[600],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            isTranquilMode ? "Relax" : "Preciso",
                            style: TextStyle(
                              color: isTranquilMode
                                  ? Colors.green[800]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
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
                        physics: const BouncingScrollPhysics(), // FISICA BOUNCY
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.green[800],
                        indicatorSize: TabBarIndicatorSize.label,
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(50),
                          color: const Color(0xFF2E7D32),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.green.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
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
                                    color: Colors.green.withOpacity(0.1),
                                    width: 1,
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
        shadowColor: Colors.black26,
        indicatorColor: Colors.green[100],
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

  Widget _buildDietView() {
    if (isLoading) return const Center(child: CircularProgressIndicator());
    if (dietData == null) return const Center(child: Text("Nessun dato"));
    return TabBarView(
      controller: _tabController,
      physics: const BouncingScrollPhysics(),
      children: days.map((day) => _buildDayList(day)).toList(),
    );
  }

  Widget _buildDayList(String day) {
    final dayPlan = dietData![day];
    if (dayPlan == null) return const Center(child: Text("Giorno Libero! 🏖️"));

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
              children: foods.asMap().entries.map((entry) {
                int index = entry.key;
                var food = entry.value;
                return _buildFoodRow(
                  day,
                  mealName,
                  index,
                  food,
                  index == foods.length - 1,
                );
              }).toList(),
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
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(24))
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                // CHECKBOX ANIMATA FLUIDA
                AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutQuint,
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
                      // TESTO CON TRANSIZIONE MORBIDA
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 300),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: inFrigo
                              ? Colors.green[800]!.withOpacity(0.5)
                              : Colors.black87,
                          decoration: inFrigo
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: Colors.green,
                        ),
                        child: Text(currentName),
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
        builder: (_, scrollController) => Padding(
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
                  controller: scrollController,
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
        onPressed: _importGroceryList,
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
                // SELETTORE UNITÀ MANUALE
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
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.kitchen, size: 80, color: Colors.green[100]),
                        const SizedBox(height: 20),
                        Text(
                          "Il frigo è vuoto!",
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
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
                                onTap: () =>
                                    setState(() => pantryItems.removeAt(index)),
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
