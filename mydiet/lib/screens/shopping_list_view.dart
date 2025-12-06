import 'package:flutter/material.dart';
import '../models/active_swap.dart';
import '../models/pantry_item.dart';

class ShoppingListView extends StatefulWidget {
  final List<String> shoppingList;
  final Map<String, dynamic>? dietData;
  final Map<String, ActiveSwap> activeSwaps;
  final List<PantryItem> pantryItems;
  final Function(List<String>) onUpdateList;

  const ShoppingListView({
    super.key,
    required this.shoppingList,
    required this.dietData,
    required this.activeSwaps,
    required this.pantryItems,
    required this.onUpdateList,
  });

  @override
  State<ShoppingListView> createState() => _ShoppingListViewState();
}

class _ShoppingListViewState extends State<ShoppingListView> {
  final Set<String> _selectedMealKeys = {};

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

  void _showImportDialog() {
    if (widget.dietData == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Carica prima una dieta!")));
      return;
    }

    final orderedDays = _getOrderedDays();

    showDialog(
      context: context,
      builder: (context) {
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
                    final dayPlan =
                        widget.dietData![day] as Map<String, dynamic>?;

                    if (dayPlan == null) return const SizedBox.shrink();

                    final mealNames = dayPlan.keys.where((k) {
                      var foods = dayPlan[k];
                      return foods is List && foods.isNotEmpty;
                    }).toList();

                    if (mealNames.isEmpty) return const SizedBox.shrink();

                    final allDayKeys = mealNames
                        .map((m) => "${day}_$m")
                        .toList();
                    bool areAllSelected = allDayKeys.every(
                      (k) => _selectedMealKeys.contains(k),
                    );

                    return ExpansionTile(
                      leading: Checkbox(
                        value: areAllSelected,
                        activeColor: Colors.green,
                        onChanged: (bool? value) {
                          setStateDialog(() {
                            if (value == true) {
                              _selectedMealKeys.addAll(allDayKeys);
                            } else {
                              _selectedMealKeys.removeAll(allDayKeys);
                            }
                          });
                        },
                      ),
                      title: Text(
                        i == 0 ? "$day (Oggi)" : day,
                        style: TextStyle(
                          fontWeight: i == 0
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: i == 0 ? Colors.green[800] : Colors.black87,
                        ),
                      ),
                      children: mealNames.map((meal) {
                        final key = "${day}_$meal";
                        final isSelected = _selectedMealKeys.contains(key);
                        return CheckboxListTile(
                          title: Text(meal),
                          value: isSelected,
                          dense: true,
                          activeColor: Colors.green,
                          contentPadding: const EdgeInsets.only(
                            left: 60,
                            right: 20,
                          ),
                          onChanged: (val) {
                            setStateDialog(() {
                              if (val == true) {
                                _selectedMealKeys.add(key);
                              } else {
                                _selectedMealKeys.remove(key);
                              }
                            });
                          },
                        );
                      }).toList(),
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
                  onPressed: () {
                    _generateListFromSelection();
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green[700],
                  ),
                  child: const Text("Importa Selezionati"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _generateListFromSelection() {
    if (_selectedMealKeys.isEmpty) return;

    // Map structure: Name -> {qty: double, unit: String}
    Map<String, Map<String, dynamic>> neededItems = {};

    try {
      // 1. Aggregate all needed items from the Diet Plan
      for (String key in _selectedMealKeys) {
        var parts = key.split('_');
        var day = parts[0];
        var meal = parts.sublist(1).join('_');

        List<dynamic>? foods = widget.dietData![day]?[meal];
        if (foods == null) continue;

        // Grouping logic (headers handling)
        List<List<dynamic>> groupedFoods = [];
        List<dynamic> currentGroup = [];

        for (var food in foods) {
          String qty = food['qty']?.toString() ?? "";
          bool isHeader = qty == "N/A";
          if (isHeader) {
            if (currentGroup.isNotEmpty) {
              groupedFoods.add(List.from(currentGroup));
            }
            currentGroup = [food];
          } else {
            if (currentGroup.isNotEmpty) {
              currentGroup.add(food);
            } else {
              groupedFoods.add([food]);
            }
          }
        }
        if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));

        // Process Groups and Swaps
        for (int i = 0; i < groupedFoods.length; i++) {
          var group = groupedFoods[i];
          String swapKey = "${day}_${meal}_group_$i";
          List<dynamic> itemsToAdd = group;

          if (widget.activeSwaps.containsKey(swapKey)) {
            final swap = widget.activeSwaps[swapKey]!;
            if (swap.swappedIngredients != null &&
                swap.swappedIngredients!.isNotEmpty) {
              itemsToAdd = swap.swappedIngredients!;
            } else {
              itemsToAdd = [
                {'name': swap.name, 'qty': swap.qty, 'unit': swap.unit},
              ];
            }
          }

          for (var food in itemsToAdd) {
            String qtyStr = food['qty']?.toString() ?? "";
            // Ignoriamo gli header (qty N/A) a meno che non siano piatti unici sostituiti
            if (qtyStr == "N/A" && itemsToAdd.length > 1) continue;
            _addToAggregator(neededItems, food['name'], qtyStr);
          }
        }
      }
    } catch (e) {
      debugPrint("Error generating list: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Errore interno nella generazione dati.")),
      );
      return;
    }

    // 2. Subtract Pantry Items
    List<String> newList = List.from(widget.shoppingList);
    int addedCount = 0;

    neededItems.forEach((name, data) {
      double neededQty = data['qty'];
      String unit = data['unit'];
      String cleanNameLower = name.trim().toLowerCase();

      // Find in Pantry
      // Logic: Matches name AND unit.
      var pantryMatch = widget.pantryItems
          .where(
            (p) =>
                p.name.toLowerCase().trim() == cleanNameLower &&
                p.unit.toLowerCase() == unit.toLowerCase(),
          )
          .firstOrNull;

      double existingQty = pantryMatch?.quantity ?? 0.0;
      double finalQty = neededQty - existingQty;

      if (finalQty > 0) {
        String displayQty = finalQty % 1 == 0
            ? finalQty.toInt().toString()
            : finalQty.toStringAsFixed(1);

        String entry = (finalQty == 0 || unit.isEmpty)
            ? name
            : "$name ($displayQty $unit)";

        if (!newList.contains(entry)) {
          newList.add(entry);
          addedCount++;
        }
      }
    });

    setState(() => _selectedMealKeys.clear());
    widget.onUpdateList(newList);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Aggiunti $addedCount prodotti (sottratto dispensa)!"),
        backgroundColor: Colors.green[700],
      ),
    );
  }

  void _addToAggregator(
    Map<String, Map<String, dynamic>> agg,
    String name,
    String qtyStr,
  ) {
    final regExp = RegExp(r'(\d+(?:[.,]\d+)?)');
    final match = regExp.firstMatch(qtyStr);

    double qty = 0.0;
    String unit = "";

    if (match != null) {
      String numPart = match.group(1)!.replaceAll(',', '.');
      qty = double.tryParse(numPart) ?? 0.0;
      unit = qtyStr.replaceAll(match.group(0)!, '').trim();
    } else {
      unit = qtyStr;
    }

    String cleanName = name.trim();
    // Use name as key to aggregate same items, store unit
    if (agg.containsKey(cleanName) && agg[cleanName]!['unit'] == unit) {
      agg[cleanName]!['qty'] += qty;
    } else {
      // Handle simple case: if unit mismatch or new item, just overwrite or add.
      // For a robust app, you'd need unit conversion.
      agg[cleanName] = {'qty': qty, 'unit': unit};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImportDialog,
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.auto_awesome, color: Colors.white),
        label: const Text(
          "Importa da Dieta",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: widget.shoppingList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_cart_outlined,
                    size: 80,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Lista Vuota",
                    style: TextStyle(color: Colors.grey[400], fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
              itemCount: widget.shoppingList.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final item = widget.shoppingList[index];
                bool isChecked = item.startsWith("OK_");
                String display = isChecked ? item.substring(3) : item;

                return Dismissible(
                  key: Key(item + index.toString()),
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  onDismissed: (_) {
                    var list = List<String>.from(widget.shoppingList);
                    list.removeAt(index);
                    widget.onUpdateList(list);
                  },
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    color: Colors.white,
                    child: CheckboxListTile(
                      value: isChecked,
                      activeColor: Colors.grey,
                      title: Text(
                        display,
                        style: TextStyle(
                          decoration: isChecked
                              ? TextDecoration.lineThrough
                              : null,
                          color: isChecked ? Colors.grey : Colors.black87,
                        ),
                      ),
                      onChanged: (val) {
                        var list = List<String>.from(widget.shoppingList);
                        if (val == true) {
                          list[index] = "OK_$display";
                        } else {
                          list[index] = display;
                        }
                        widget.onUpdateList(list);
                      },
                    ),
                  ),
                );
              },
            ),
    );
  }
}
