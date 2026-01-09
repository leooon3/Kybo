import '../models/diet_models.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class DietEngine {
  // --- CORE: Calcolo Ingredienti Necessari (Shopping & Inventory) ---
  static Map<String, double> calculateRequirements({
    required DietPlan plan,
    required Map<String, ActiveSwap> swaps,
    int daysFromToday = 7,
  }) {
    final Map<String, double> requirements = {};
    final daysOfInterest = _getOrderedDaysFromToday();

    for (var day in daysOfInterest) {
      final dailyPlan = plan.weeklyPlan[day];
      if (dailyPlan == null) continue;

      for (var meal in dailyPlan.meals.values) {
        for (var dish in meal.dishes) {
          final String swapKey = "${day}_${meal.name}_${dish.cadCode}";

          if (swaps.containsKey(swapKey)) {
            _addSwapToRequirements(requirements, swaps[swapKey]!);
          } else {
            _addDishToRequirements(requirements, dish);
          }
        }
      }
    }
    return requirements;
  }

  // --- CORE: Calcolo Disponibilità UI (Tick Verdi) ---
  static Map<String, bool> calculateAvailability(
    DietPlan plan,
    List<PantryItem> pantry,
    Map<String, ActiveSwap> swaps,
  ) {
    final Map<String, bool> availability = {};
    final Map<String, double> virtualPantry = _pantryToMap(pantry);
    final orderedDays = _getOrderedDaysFromToday();

    for (var day in orderedDays) {
      final dailyPlan = plan.weeklyPlan[day];
      if (dailyPlan == null) continue;

      // [MODIFICA] Rimossa _sortMeals. Usiamo l'ordine naturale dei dati.
      // Firebase/JSON solitamente mantengono l'ordine di inserimento se generati correttamente.
      final meals = dailyPlan.meals.values.toList();

      for (var meal in meals) {
        for (int i = 0; i < meal.dishes.length; i++) {
          final dish = meal.dishes[i];
          final String uiKey = "${day}_${meal.name}_$i";

          if (dish.isConsumed) {
            availability[uiKey] = false;
            continue;
          }

          final String swapKey = "${day}_${meal.name}_${dish.cadCode}";
          bool hasIngredients = false;

          if (swaps.containsKey(swapKey)) {
            hasIngredients = _consumeFromVirtualPantry(
              virtualPantry,
              swaps[swapKey]!,
            );
          } else {
            hasIngredients = _consumeDishFromVirtualPantry(virtualPantry, dish);
          }

          availability[uiKey] = hasIngredients;
        }
      }
    }
    return availability;
  }

  // --- HELPERS DI CONVERSIONE INTELLIGENTE [NEW] ---

  /// Tenta di sottrarre la quantità richiesta dalla dispensa, gestendo le conversioni
  static bool _deduct(
    Map<String, double> pantry,
    String name,
    double qty,
    String unit,
  ) {
    final cleanName = name.trim().toLowerCase();
    final cleanUnit = unit.trim().toLowerCase();
    final directKey = "$cleanName||$cleanUnit";

    // 1. Tenta Match Esatto (Stessa unità)
    if (pantry.containsKey(directKey)) {
      return _performDeduct(pantry, directKey, qty);
    }

    // 2. Tenta Match con Conversione (Stesso nome, unità compatibile)
    // Es: Richiede 'g', Dispensa ha 'kg'
    for (var pantryKey in pantry.keys) {
      if (pantryKey.startsWith("$cleanName||")) {
        final parts = pantryKey.split("||");
        final pantryUnit = parts.length > 1 ? parts[1] : "";

        // Calcola fattore di conversione (es. g -> kg = 0.001)
        final factor = _getConversionFactor(cleanUnit, pantryUnit);

        if (factor != null) {
          final convertedReqQty = qty * factor;
          return _performDeduct(pantry, pantryKey, convertedReqQty);
        }
      }
    }

    return false; // Non trovato o unità incompatibili
  }

  static bool _performDeduct(
    Map<String, double> pantry,
    String key,
    double amount,
  ) {
    final current = pantry[key]!;
    // Tolleranza per errori di virgola mobile (es. 0.99999 vs 1.0)
    if (current >= amount - 0.0001) {
      pantry[key] = (current - amount < 0) ? 0 : current - amount;
      return true;
    } else {
      pantry[key] = 0; // Consuma parzialmente (opzionale, logica di business)
      return false; // Non basta
    }
  }

  static double? _getConversionFactor(String from, String to) {
    if (from == to) return 1.0;

    // Fattori di normalizzazione verso unità base (g, ml)
    const normalize = {
      'kg': 1000.0,
      'hg': 100.0,
      'g': 1.0,
      'gr': 1.0,
      'grammi': 1.0,
      'l': 1000.0,
      'lt': 1000.0,
      'dl': 100.0,
      'cl': 10.0,
      'ml': 1.0,
      'pz': 1.0,
      'pezzi': 1.0,
    };

    final fromVal = normalize[from];
    final toVal = normalize[to];

    if (fromVal != null && toVal != null) {
      // Controllo di compatibilità (Massa vs Massa, Volume vs Volume)
      bool isMass(String u) => ['kg', 'hg', 'g', 'gr', 'grammi'].contains(u);
      bool isVol(String u) => ['l', 'lt', 'dl', 'cl', 'ml'].contains(u);

      if ((isMass(from) && isMass(to)) || (isVol(from) && isVol(to))) {
        return fromVal / toVal;
      }
    }
    return null; // Incompatibili (es. pz vs kg)
  }

  // --- ALTRI HELPERS ---

  static void _addDishToRequirements(Map<String, double> req, Dish dish) {
    if (dish.ingredients.isNotEmpty) {
      for (var ing in dish.ingredients) {
        _addToMap(req, ing.name, ing.qty, ing.rawUnit);
      }
    } else {
      _addToMap(req, dish.name, dish.qty, dish.rawUnit);
    }
  }

  static void _addSwapToRequirements(Map<String, double> req, ActiveSwap swap) {
    if (swap.swappedIngredients != null &&
        swap.swappedIngredients!.isNotEmpty) {
      for (var ing in swap.swappedIngredients!) {
        final name = ing['name'].toString();
        final qty = double.tryParse(ing['qty'].toString()) ?? 1.0;
        final unit = ing['unit']?.toString() ?? 'pz';
        _addToMap(req, name, qty, unit);
      }
    } else {
      _addToMap(req, swap.name, double.tryParse(swap.qty) ?? 1.0, swap.unit);
    }
  }

  static void _addToMap(
    Map<String, double> map,
    String name,
    double qty,
    String unit,
  ) {
    final key = "${name.trim().toLowerCase()}||${unit.trim().toLowerCase()}";
    map[key] = (map[key] ?? 0.0) + qty;
  }

  static bool _consumeDishFromVirtualPantry(
    Map<String, double> pantry,
    Dish dish,
  ) {
    if (dish.ingredients.isNotEmpty) {
      bool allOk = true;
      for (var ing in dish.ingredients) {
        if (!_deduct(pantry, ing.name, ing.qty, ing.rawUnit)) allOk = false;
      }
      return allOk;
    }
    return _deduct(pantry, dish.name, dish.qty, dish.rawUnit);
  }

  static bool _consumeFromVirtualPantry(
    Map<String, double> pantry,
    ActiveSwap swap,
  ) {
    if (swap.swappedIngredients != null &&
        swap.swappedIngredients!.isNotEmpty) {
      bool allOk = true;
      for (var ing in swap.swappedIngredients!) {
        final name = ing['name'].toString();
        final qty = double.tryParse(ing['qty'].toString()) ?? 0.0;
        final unit = ing['unit']?.toString() ?? '';
        if (!_deduct(pantry, name, qty, unit)) allOk = false;
      }
      return allOk;
    }
    return _deduct(
      pantry,
      swap.name,
      double.tryParse(swap.qty) ?? 0.0,
      swap.unit,
    );
  }

  static Map<String, double> _pantryToMap(List<PantryItem> items) {
    final Map<String, double> map = {};
    for (var i in items) {
      final key =
          "${i.name.trim().toLowerCase()}||${i.unit.trim().toLowerCase()}";
      map[key] = (map[key] ?? 0.0) + i.quantity;
    }
    return map;
  }

  static List<String> _getOrderedDaysFromToday() {
    final days = [
      "Lunedì",
      "Martedì",
      "Mercoledì",
      "Giovedì",
      "Venerdì",
      "Sabato",
      "Domenica",
    ];
    final today = DateTime.now().weekday - 1;
    final start = (today >= 0 && today < 7) ? today : 0;
    return [...days.sublist(start), ...days.sublist(0, start)];
  }
}
