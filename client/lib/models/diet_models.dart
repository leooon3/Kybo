import 'package:uuid/uuid.dart';

// --- ENUMS & COSTANTI ---
enum UnitType { g, ml, pz, unknown }

class DietConstants {
  static UnitType parseUnit(String raw) {
    final clean = raw.trim().toLowerCase();
    if (clean == 'g' || clean == 'gr' || clean == 'grammi') return UnitType.g;
    if (clean == 'ml' || clean == 'l' || clean == 'lt') return UnitType.ml;
    if (clean == 'pz' || clean == 'pezzi' || clean == 'fette') {
      return UnitType.pz;
    }
    return UnitType.unknown;
  }

  static String unitToString(UnitType u) => u.name;
}

// --- MODELLI CORE ---

class Ingredient {
  final String name;
  final double qty;
  final UnitType unit;
  final String rawUnit; // Manteniamo l'originale per UI legacy

  Ingredient({
    required this.name,
    required this.qty,
    required this.unit,
    this.rawUnit = '',
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final rawQ = json['qty']?.toString() ?? '0';
    // Logica di parsing qty spostata qui per sicurezza
    final double parsedQty =
        double.tryParse(
          rawQ.replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.'),
        ) ??
        0.0;
    final String rawU = json['unit']?.toString() ?? '';

    return Ingredient(
      name: json['name']?.toString() ?? 'Ingrediente sconosciuto',
      qty: parsedQty,
      unit: DietConstants.parseUnit(rawU),
      rawUnit: rawU,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'unit': rawUnit, // Serializziamo come stringa per compatibilità backend
  };
}

class Dish {
  final String id; // UUID Obbligatorio
  final String name;
  final double qty;
  final String rawUnit;
  final int cadCode; // Per backward compatibility con vecchi swap
  final List<Ingredient> ingredients;
  bool isConsumed;

  Dish({
    required this.id,
    required this.name,
    required this.qty,
    required this.rawUnit,
    this.cadCode = 0,
    this.ingredients = const [],
    this.isConsumed = false,
  });

  factory Dish.fromJson(Map<String, dynamic> json) {
    return Dish(
      id:
          json['instance_id']?.toString() ??
          const Uuid().v4(), // Auto-fix se manca ID
      name: json['name']?.toString() ?? 'Piatto',
      qty: double.tryParse(json['qty']?.toString() ?? '1') ?? 1.0,
      rawUnit: json['unit']?.toString() ?? 'pz',
      cadCode: int.tryParse(json['cad_code']?.toString() ?? '0') ?? 0,
      ingredients:
          (json['ingredients'] as List?)
              ?.map((e) => Ingredient.fromJson(e))
              .toList() ??
          [],
      isConsumed: json['consumed'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'instance_id': id,
    'name': name,
    'qty': qty,
    'unit': rawUnit,
    'cad_code': cadCode,
    'ingredients': ingredients.map((e) => e.toJson()).toList(),
    'consumed': isConsumed,
  };
}

class Meal {
  final String id;
  final String name; // "Colazione", "Pranzo"...
  final List<Dish> dishes;

  Meal({required this.id, required this.name, required this.dishes});

  factory Meal.fromJson(String name, List<dynamic> jsonList) {
    return Meal(
      id: "${name}_${const Uuid().v4()}",
      name: name,
      dishes: jsonList.map((e) => Dish.fromJson(e)).toList(),
    );
  }

  List<dynamic> toJson() => dishes.map((e) => e.toJson()).toList();
}

class DailyPlan {
  final String dayName; // "Lunedì"
  final Map<String, Meal> meals; // Key: "Colazione"

  DailyPlan({required this.dayName, required this.meals});

  factory DailyPlan.fromJson(String day, Map<String, dynamic> json) {
    final Map<String, Meal> parsedMeals = {};
    json.forEach((key, value) {
      if (value is List) {
        parsedMeals[key] = Meal.fromJson(key, value);
      }
    });
    return DailyPlan(dayName: day, meals: parsedMeals);
  }

  Map<String, dynamic> toJson() {
    return meals.map((key, value) => MapEntry(key, value.toJson()));
  }
}

class DietPlan {
  final Map<String, DailyPlan> weeklyPlan;
  final Map<String, dynamic>
  substitutions; // Lasciamo dinamico per ora, meno critico

  DietPlan({required this.weeklyPlan, required this.substitutions});

  factory DietPlan.fromJson(Map<String, dynamic> json) {
    final Map<String, DailyPlan> plan = {};
    final planJson = json['plan'] as Map<String, dynamic>? ?? {};

    planJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        plan[key] = DailyPlan.fromJson(key, value);
      }
    });

    return DietPlan(
      weeklyPlan: plan,
      substitutions: json['substitutions'] ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'plan': weeklyPlan.map((k, v) => MapEntry(k, v.toJson())),
    'substitutions': substitutions,
  };
}
