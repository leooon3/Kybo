import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../constants.dart';
import 'diet_view.dart';
import 'shopping_list_view.dart';
import 'pantry_view.dart';
// import 'history_screen.dart'; // Se serve

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const DietView(), // Niente parametri!
    const ShoppingListView(), // Niente parametri!
    const PantryView(),
  ];

  @override
  void initState() {
    super.initState();
    // Carica dati all'avvio
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DietProvider>(context, listen: false).loadFromCache();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DietProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          "Kybo",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Tranquil Mode Toggle
          IconButton(
            icon: Icon(
              provider.isTranquilMode ? Icons.spa : Icons.spa_outlined,
              color: provider.isTranquilMode ? Colors.green : Colors.grey,
            ),
            onPressed: () => provider.toggleTranquilMode(),
          ),
          // Settings / Clear Data
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings, color: Colors.black),
            onSelected: (val) {
              if (val == 'clear') {
                provider.clearData();
              } else if (val == 'upload') {
                // Naviga a upload screen o mostra dialog
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'clear', child: Text("Reset Dati")),
            ],
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
        onTap: (idx) => setState(() => _currentIndex = idx),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.restaurant), label: "Dieta"),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart),
            label: "Spesa",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.kitchen), label: "Dispensa"),
        ],
      ),
      floatingActionButton:
          _currentIndex ==
              2 // Solo su Pantry
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              child: const Icon(Icons.qr_code_scanner),
              onPressed: () async {
                // Logica Scan (se implementata UI)
              },
            )
          : null,
    );
  }
}
