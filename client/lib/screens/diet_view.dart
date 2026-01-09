import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../models/diet_models.dart';
import '../models/active_swap.dart';
import '../widgets/meal_card.dart';
import '../constants.dart';

class DietView extends StatefulWidget {
  const DietView({super.key});

  @override
  State<DietView> createState() => _DietViewState();
}

class _DietViewState extends State<DietView> {
  // Gestione tab giorni
  final List<String> _days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];
  late int _selectedDayIndex;

  // Ordine pasti UI
  final List<String> _orderedMealTypes = [
    "Colazione",
    "Seconda Colazione",
    "Spuntino",
    "Pranzo",
    "Merenda",
    "Cena",
    "Spuntino Serale",
    "Nell'Arco Della Giornata",
  ];

  @override
  void initState() {
    super.initState();
    // Seleziona il giorno corrente
    int today = DateTime.now().weekday - 1;
    _selectedDayIndex = (today >= 0 && today < 7) ? today : 0;
  }

  void _showSwapDialog(
    BuildContext context,
    String day,
    String mealName,
    int cadCode,
  ) {
    final provider = Provider.of<DietProvider>(context, listen: false);

    // Trova le opzioni nel DietPlan
    final substitutions =
        provider.substitutions; // Ora accessibile via getter alias
    final String cadKey = cadCode.toString();

    if (!substitutions.containsKey(cadKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Nessuna alternativa disponibile.")),
      );
      return;
    }

    final group = substitutions[cadKey];
    final String title = group['name'] ?? 'Sostituzioni';
    final List<dynamic> options = group['options'] ?? [];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Sostituisci: $title",
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  itemCount: options.length + 1, // +1 per "Rimuovi Swap"
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        leading: const Icon(Icons.undo, color: Colors.red),
                        title: const Text("Ripristina Originale"),
                        onTap: () {
                          // Rimuovi swap logic (dovrebbe essere aggiunto al provider, o passiamo null)
                          // Per ora implementiamo con activeSwaps.remove se esposto o aggiungi metodo removeSwap
                          // provider.removeSwap(day, mealName, cadCode);
                          Navigator.pop(context);
                        },
                      );
                    }
                    final opt = options[index - 1];
                    return ListTile(
                      leading: const Icon(
                        Icons.restaurant_menu,
                        color: AppColors.primary,
                      ),
                      title: Text(opt['name']),
                      subtitle: Text(
                        "${opt['qty']}",
                      ), // Unit spesso inclusa nella stringa legacy o aggiungere 'unit'
                      onTap: () {
                        provider.executeSwap(
                          day,
                          mealName,
                          cadCode,
                          ActiveSwap(
                            name: opt['name'],
                            qty: opt['qty'].toString(),
                            unit: '',
                          ),
                        );
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DietProvider>(
      builder: (context, provider, child) {
        final plan = provider.dietPlan;

        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (plan == null) {
          return const Center(child: Text("Nessuna dieta caricata."));
        }

        final String currentDayName = _days[_selectedDayIndex];
        final DailyPlan? dailyPlan = plan.weeklyPlan[currentDayName];

        return Column(
          children: [
            // DAY SELECTOR
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
              child: Row(
                children: _days.asMap().entries.map((entry) {
                  int idx = entry.key;
                  String dayName = entry.value;
                  bool isSelected = idx == _selectedDayIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(dayName.substring(0, 3).toUpperCase()),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      onSelected: (bool selected) {
                        if (selected) setState(() => _selectedDayIndex = idx);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),

            // MEAL LIST
            Expanded(
              child: dailyPlan == null || dailyPlan.meals.isEmpty
                  ? const Center(child: Text("Nessun pasto previsto per oggi."))
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 80),
                      children: _orderedMealTypes.map((mealType) {
                        if (!dailyPlan.meals.containsKey(mealType)) {
                          return const SizedBox.shrink();
                        }

                        final Meal meal = dailyPlan.meals[mealType]!;

                        return MealCard(
                          day: currentDayName,
                          mealName: mealType,
                          foods: meal.dishes, // List<Dish> OK
                          activeSwaps: provider.activeSwaps,
                          availabilityMap: provider.availabilityMap,
                          isTranquilMode: provider.isTranquilMode,
                          isToday:
                              (DateTime.now().weekday - 1) == _selectedDayIndex,

                          // Nuove Callback
                          onEat: (dishIndex) {
                            provider.toggleMealConsumed(
                              currentDayName,
                              mealType,
                              dishIndex,
                            );
                          },
                          onSwap: (swapKey, cadCode) {
                            _showSwapDialog(
                              context,
                              currentDayName,
                              mealType,
                              cadCode,
                            );
                          },
                        );
                      }).toList(),
                    ),
            ),
          ],
        );
      },
    );
  }
}
