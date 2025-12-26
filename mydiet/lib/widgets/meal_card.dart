import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/active_swap.dart';
import '../constants.dart';
import '../providers/diet_provider.dart';

class MealCard extends StatelessWidget {
  final String day;
  final String mealName;
  final List<dynamic> foods;
  final Map<String, ActiveSwap> activeSwaps;
  final bool isTranquilMode;
  final Function(String key, int currentCad) onSwap;
  final Function(int index, String name, String qty)? onEdit;

  const MealCard({
    super.key,
    required this.day,
    required this.mealName,
    required this.foods,
    required this.activeSwaps,
    required this.isTranquilMode,
    required this.onSwap,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    // Check Day
    final italianDays = [
      "Lunedì",
      "Martedì",
      "Mercoledì",
      "Giovedì",
      "Venerdì",
      "Sabato",
      "Domenica",
    ];
    final todayIndex = DateTime.now().weekday - 1;
    bool isToday = false;
    if (todayIndex >= 0 && todayIndex < italianDays.length) {
      isToday = day.toLowerCase() == italianDays[todayIndex].toLowerCase();
    }

    // Grouping
    List<List<dynamic>> groupedFoods = [];
    List<dynamic> currentGroup = [];
    for (var food in foods) {
      String qty = food['qty']?.toString() ?? "";
      bool isHeader = qty == "N/A";
      if (isHeader) {
        if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));
        currentGroup = [food];
      } else {
        if (currentGroup.isNotEmpty)
          currentGroup.add(food);
        else
          groupedFoods.add([food]);
      }
    }
    if (currentGroup.isNotEmpty) groupedFoods.add(List.from(currentGroup));

    int globalIndex = 0;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compact Header
            Text(
              mealName.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 8),

            ...groupedFoods.asMap().entries.map((entry) {
              int groupIndex = entry.key;
              List<dynamic> group = entry.value;
              int currentGroupStart = globalIndex;
              globalIndex += group.length;

              if (group.isEmpty) return const SizedBox.shrink();

              // Logic
              final String availabilityKey =
                  "${day}_${mealName}_$currentGroupStart";
              final isAvailable =
                  Provider.of<DietProvider>(
                    context,
                  ).availabilityMap[availabilityKey] ??
                  false;

              var header = group[0];
              int cadCode =
                  int.tryParse(header['cad_code']?.toString() ?? "0") ?? 0;
              String swapKey = "${day}_${mealName}_group_$groupIndex";
              bool isSwapped = activeSwaps.containsKey(swapKey);

              List<dynamic> itemsToShow;
              if (isSwapped) {
                final swap = activeSwaps[swapKey]!;
                if (swap.swappedIngredients != null &&
                    swap.swappedIngredients!.isNotEmpty) {
                  itemsToShow = swap.swappedIngredients!;
                } else {
                  String q = swap.qty;
                  if (swap.unit.isNotEmpty) q += " ${swap.unit}";
                  itemsToShow = [
                    {'name': swap.name, 'qty': q},
                  ];
                }
              } else {
                itemsToShow = [];
                for (var item in group) {
                  itemsToShow.add(item);
                  if (item['ingredients'] != null &&
                      (item['ingredients'] as List).isNotEmpty) {
                    itemsToShow.addAll(item['ingredients']);
                  }
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                  border: isAvailable
                      ? Border.all(
                          color: Colors.green.withOpacity(0.3),
                          width: 1,
                        )
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status Icon (Compact)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, right: 8),
                      child: Icon(
                        isAvailable ? Icons.kitchen : Icons.restaurant_menu,
                        color: isAvailable ? Colors.green : Colors.grey[300],
                        size: 16,
                      ),
                    ),

                    // Food Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: itemsToShow.asMap().entries.map((itemEntry) {
                          var item = itemEntry.value;
                          String name = item['name']?.toString() ?? "Piatto";
                          String qty = item['qty']?.toString() ?? "";
                          bool isHeaderItem = (qty == "N/A" || qty.isEmpty);

                          if (isTranquilMode) {
                            /* ... same logic ... */
                          }

                          String textDisplay = (isHeaderItem || qty.isEmpty)
                              ? name
                              : "$name ($qty)";

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              textDisplay,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.2,
                                color: isSwapped
                                    ? Colors.blueGrey
                                    : Colors.black87,
                                fontWeight: (isHeaderItem && !isSwapped)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Compact Actions
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (cadCode > 0)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              icon: const Icon(Icons.swap_horiz, size: 18),
                              color: Colors.blueGrey,
                              padding: EdgeInsets.zero,
                              onPressed: () => onSwap(swapKey, cadCode),
                            ),
                          ),
                        if (isToday)
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: IconButton(
                              icon: const Icon(Icons.check, size: 18),
                              color: Colors.green,
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              onPressed: () {
                                Provider.of<DietProvider>(
                                  context,
                                  listen: false,
                                ).consumeMeal(day, mealName, currentGroupStart);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Rimosso dal frigo"),
                                    duration: Duration(milliseconds: 800),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
