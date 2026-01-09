import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../constants.dart';
// Rimosso import inutile diet_models.dart

class ShoppingListView extends StatefulWidget {
  const ShoppingListView({super.key});

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState extends State<ShoppingListView> {
  final Set<String> _selectedDays = {};

  final List<String> _allDays = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];

  List<String> _getOrderedDays() {
    int todayIndex = DateTime.now().weekday - 1;
    if (todayIndex < 0 || todayIndex > 6) todayIndex = 0;
    return [
      ..._allDays.sublist(todayIndex),
      ..._allDays.sublist(0, todayIndex),
    ];
  }

  void _showImportDialog(BuildContext context) {
    final provider = Provider.of<DietProvider>(context, listen: false);
    final plan = provider.dietPlan;

    if (plan == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Carica prima una dieta!")));
      return;
    }

    final orderedDays = _getOrderedDays();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Genera Lista Spesa"),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: orderedDays.length,
                  itemBuilder: (context, i) {
                    final day = orderedDays[i];
                    final dayExists = plan.weeklyPlan.containsKey(day);
                    if (!dayExists) return const SizedBox.shrink();

                    final isSelected = _selectedDays.contains(day);

                    return CheckboxListTile(
                      activeColor: AppColors.primary,
                      title: Text(
                        i == 0 ? "$day (Oggi)" : day,
                        style: TextStyle(
                          fontWeight: i == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: i == 0 ? AppColors.primary : Colors.black87,
                        ),
                      ),
                      value: isSelected,
                      onChanged: (val) {
                        setStateDialog(() {
                          if (val == true) {
                            _selectedDays.add(day);
                          } else {
                            _selectedDays.remove(day);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Annulla"),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  onPressed: () {
                    provider.generateShoppingList(_selectedDays.toList());
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Lista generata! Controlla eventuali swap.",
                        ),
                        backgroundColor: AppColors.primary,
                      ),
                    );
                  },
                  child: const Text("Importa"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _moveCheckedToPantry(DietProvider provider) {
    int count = 0;
    final currentList = List<String>.from(provider.shoppingList);

    for (String itemRaw in currentList) {
      if (itemRaw.startsWith("OK_")) {
        String content = itemRaw.substring(3);
        final RegExp regExp = RegExp(
          r'^(.*?)(?:\s*\((\d+(?:[.,]\d+)?)\s*(.*)\))?$',
        );
        final match = regExp.firstMatch(content);

        String name = content;
        double qty = 1.0;
        String unit = "pz";

        if (match != null) {
          name = match.group(1)?.trim() ?? content;
          String? qtyStr = match.group(2);
          String? unitStr = match.group(3);
          if (qtyStr != null) {
            qty = double.tryParse(qtyStr.replaceAll(',', '.')) ?? 1.0;
          }
          if (unitStr != null && unitStr.isNotEmpty) {
            unit = unitStr.trim();
          }
        }

        provider.addPantryItem(name, qty, unit);
        count++;
      }
    }

    // [FIX] Ora usiamo la variabile newList e il nuovo metodo del provider
    final newList = provider.shoppingList
        .where((i) => !i.startsWith("OK_"))
        .toList();
    provider.updateShoppingList(newList);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("$count prodotti spostati in dispensa!")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DietProvider>(
      builder: (context, provider, child) {
        final shoppingList = provider.shoppingList;
        final bool hasCheckedItems = shoppingList.any(
          (i) => i.startsWith("OK_"),
        );

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          body: SafeArea(
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_cart,
                        size: 28,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 10),
                      Text(
                        "Lista della Spesa",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: shoppingList.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.list_alt,
                                size: 60,
                                color: Colors.grey[300],
                              ),
                              const Text("Lista Vuota"),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: shoppingList.length,
                          itemBuilder: (context, index) {
                            String raw = shoppingList[index];
                            bool isChecked = raw.startsWith("OK_");
                            String display = isChecked ? raw.substring(3) : raw;

                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.03),
                                    blurRadius: 5,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Dismissible(
                                key: Key(raw + index.toString()),
                                onDismissed: (_) {
                                  var list = List<String>.from(shoppingList);
                                  list.removeAt(index);
                                  // [FIX] Aggiornamento tramite provider
                                  provider.updateShoppingList(list);
                                },
                                background: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: Icon(
                                    Icons.delete,
                                    color: Colors.red[800],
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: isChecked,
                                  activeColor: AppColors.primary,
                                  checkColor: Colors.white,
                                  title: Text(
                                    display,
                                    style: TextStyle(
                                      decoration: isChecked
                                          ? TextDecoration.lineThrough
                                          : null,
                                      color: isChecked
                                          ? Colors.grey
                                          : const Color(0xFF2D3436),
                                    ),
                                  ),
                                  onChanged: (val) {
                                    var list = List<String>.from(shoppingList);
                                    list[index] = val == true
                                        ? "OK_$display"
                                        : display;
                                    provider.updateShoppingList(list);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),

                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: hasCheckedItems
                                ? AppColors.primary
                                : Colors.grey,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: hasCheckedItems
                              ? () => _moveCheckedToPantry(provider)
                              : null,
                          icon: const Icon(Icons.kitchen, color: Colors.white),
                          label: const Text(
                            "Sposta nel Frigo",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            side: const BorderSide(color: AppColors.accent),
                          ),
                          onPressed: () => _showImportDialog(context),
                          icon: const Icon(
                            Icons.download,
                            color: AppColors.accent,
                          ),
                          label: const Text(
                            "Importa da Dieta",
                            style: TextStyle(color: AppColors.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
