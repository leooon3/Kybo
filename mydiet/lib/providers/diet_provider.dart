import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../services/api_client.dart';

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();

  // Data States
  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];
  Map<String, bool> _availabilityMap = {};

  // UI States
  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error;

  // Getters
  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  List<String> get shoppingList => _shoppingList;
  Map<String, bool> get availabilityMap => _availabilityMap;
  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;
  String? get error => _error;
  bool get hasError => _error != null;

  DietProvider(this._repository) {
    _init();
  }

  Future<void> _init() async {
    try {
      final savedDiet = await _storage.loadDiet();
      if (savedDiet != null) {
        _dietData = savedDiet['plan'];
        _substitutions = savedDiet['substitutions'];
      }
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();
      _recalcAvailability();
    } catch (e) {
      debugPrint("Init Load Error: $e");
    }
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    clearError();

    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (e) {
        debugPrint("FCM Warning: $e");
      }

      final result = await _repository.uploadDiet(path, fcmToken: token);

      _dietData = result.plan;
      _substitutions = result.substitutions;

      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });

      if (_auth.currentUser != null) {
        await _firestore.saveDietToHistory(_dietData!, _substitutions!);
      }

      _activeSwaps = {};
      await _storage.saveSwaps({});
      _recalcAvailability();
    } catch (e) {
      _error = _mapError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<int> scanReceipt(String path) async {
    _setLoading(true);
    clearError();
    int count = 0;
    try {
      List<String> allowedFoods = _extractAllowedFoods();

      final items = await _repository.scanReceipt(path, allowedFoods);

      for (var item in items) {
        if (item is Map && item.containsKey('name')) {
          double qty = 1.0;
          if (item['quantity'] != null) {
            qty = double.tryParse(item['quantity'].toString()) ?? 1.0;
          }
          addPantryItem(item['name'], qty, 'pz');
          count++;
        }
      }
    } catch (e) {
      _error = _mapError(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
    return count;
  }

  // --- [FIX] ROBUST DUPLICATE CHECKING ---
  void addPantryItem(String name, double qty, String unit) {
    final normalizedName = name.trim().toLowerCase();
    final normalizedUnit = unit.trim().toLowerCase();

    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.trim().toLowerCase() == normalizedName &&
          p.unit.trim().toLowerCase() == normalizedUnit,
    );

    if (index != -1) {
      _pantryItems[index].quantity += qty;
    } else {
      // Capitalize first letter for display
      String displayName = name.trim();
      if (displayName.isNotEmpty) {
        displayName =
            "${displayName[0].toUpperCase()}${displayName.substring(1)}";
      }
      _pantryItems.add(
        PantryItem(name: displayName, quantity: qty, unit: unit),
      );
    }
    _storage.savePantry(_pantryItems);
    _recalcAvailability();
    notifyListeners();
  }

  void consumeMeal(String day, String mealType, int dishIndex) {
    if (_dietData == null || _dietData![day] == null) return;

    final meals = _dietData![day][mealType];
    if (meals == null || meals is! List || dishIndex >= meals.length) return;

    final dish = meals[dishIndex];

    if (dish['ingredients'] != null &&
        (dish['ingredients'] as List).isNotEmpty) {
      for (var ing in dish['ingredients']) {
        final iName = ing['name'].toString();
        final iQtyRaw = ing['qty'].toString();
        consumeSmart(iName, iQtyRaw);
      }
    } else {
      consumeSmart(dish['name'], dish['qty'] ?? '1');
    }
  }

  void consumeSmart(String name, String rawQtyString) {
    double qtyToEat = _parseQty(rawQtyString);
    String unit = rawQtyString.toLowerCase().contains('g') ? 'g' : 'pz';
    consumeItem(name, qtyToEat, unit);
  }

  // --- [FIX] SMARTER CONSUMPTION LOGIC ---
  void consumeItem(String name, double qty, String unit) {
    final searchName = name.trim().toLowerCase();
    final searchUnit = unit.trim().toLowerCase();

    // Strategy 1: Exact Match (Name + Unit)
    int index = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase() == searchName &&
          p.unit.toLowerCase() == searchUnit,
    );

    // Strategy 2: Fuzzy Name Match (Bidirectional Contains)
    if (index == -1) {
      index = _pantryItems.indexWhere((p) {
        final pName = p.name.toLowerCase();
        return (pName.contains(searchName) || searchName.contains(pName));
      });
    }

    if (index != -1) {
      var item = _pantryItems[index];

      // Handle Unit Mismatch Logic
      // If diet wants 'g' but fridge has 'pz', just subtract 1 pz as fallback
      double qtyToSubtract = qty;
      if (item.unit.toLowerCase() != searchUnit) {
        qtyToSubtract = 1.0;
      }

      item.quantity -= qtyToSubtract;

      if (item.quantity <= 0.01) {
        _pantryItems.removeAt(index);
      }

      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  void removePantryItem(int index) {
    if (index >= 0 && index < _pantryItems.length) {
      _pantryItems.removeAt(index);
      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  // --- Tomato Availability Simulation ---
  void _recalcAvailability() {
    if (_dietData == null) return;

    Map<String, double> simulatedFridge = {};
    for (var item in _pantryItems) {
      simulatedFridge[item.name.trim().toLowerCase()] = item.quantity;
    }

    Map<String, bool> newMap = {};
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

    for (int d = 0; d < italianDays.length; d++) {
      if (d < todayIndex) continue;

      String day = italianDays[d];
      if (!_dietData!.containsKey(day)) continue;

      final mealsOfDay = _dietData![day] as Map<String, dynamic>;
      final mealTypes = [
        "Colazione",
        "Seconda Colazione",
        "Pranzo",
        "Merenda",
        "Cena",
        "Spuntino Serale",
      ];

      for (var mType in mealTypes) {
        if (!mealsOfDay.containsKey(mType)) continue;

        List<dynamic> dishes = List.from(mealsOfDay[mType]);

        for (int i = 0; i < dishes.length; i++) {
          final dish = dishes[i];
          bool isCovered = true;

          List<dynamic> itemsToCheck = [];
          if (dish['ingredients'] != null &&
              (dish['ingredients'] as List).isNotEmpty) {
            itemsToCheck = dish['ingredients'];
          } else {
            itemsToCheck = [
              {'name': dish['name'], 'qty': dish['qty']},
            ];
          }

          for (var item in itemsToCheck) {
            String iName = item['name'].toString().trim().toLowerCase();
            double iQty = _parseQty(item['qty'].toString());

            String? foundKey;
            for (var key in simulatedFridge.keys) {
              // Fuzzy Match for Simulation
              if (key.contains(iName) || iName.contains(key)) {
                foundKey = key;
                break;
              }
            }

            if (foundKey != null && simulatedFridge[foundKey]! > 0) {
              // Simple subtraction logic for simulation
              // If unit mismatch, we assume 1pz covers typical gram requests for simplicity in boolean check
              double sub = iQty;
              // If fridge has 'pz' (count < 50) and diet asks for > 50 (grams), treat 1 pz as coverage
              if (simulatedFridge[foundKey]! < 50 && iQty > 50) sub = 1.0;

              if (simulatedFridge[foundKey]! >= sub) {
                simulatedFridge[foundKey] = simulatedFridge[foundKey]! - sub;
              } else {
                isCovered = false; // Partial stock counts as missing for safety
              }
            } else {
              isCovered = false;
            }
          }
          newMap["${day}_${mType}_$i"] = isCovered;
        }
      }
    }
    _availabilityMap = newMap;
  }

  double _parseQty(String raw) {
    final regExp = RegExp(r'(\d+[.,]?\d*)');
    final match = regExp.firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }
    return 1.0;
  }

  String _mapError(Object e) {
    if (e is ApiException) return "Server Error: ${e.message}";
    if (e is NetworkException) return "Problema di connessione. Riprova.";
    return "Errore imprevisto: $e";
  }

  // --- Boilerplate Preserved ---
  void loadHistoricalDiet(Map<String, dynamic> dietData) {
    _dietData = dietData['plan'];
    _substitutions = dietData['substitutions'];
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _activeSwaps = {};
    _storage.saveSwaps({});
    _recalcAvailability();
    notifyListeners();
  }

  List<String> _extractAllowedFoods() {
    final Set<String> foods = {};
    if (_dietData != null) {
      _dietData!.forEach((day, meals) {
        if (meals is Map) {
          meals.forEach((mealType, dishes) {
            if (dishes is List) {
              for (var d in dishes) {
                foods.add(d['name']);
              }
            }
          });
        }
      });
    }
    if (_substitutions != null) {
      _substitutions!.forEach((key, group) {
        if (group['options'] is List) {
          for (var opt in group['options']) {
            foods.add(opt['name']);
          }
        }
      });
    }
    return foods.toList();
  }

  void updateShoppingList(List<String> list) {
    _shoppingList = list;
    notifyListeners();
  }

  Future<void> clearData() async {
    await _storage.clearAll();
    _dietData = null;
    _substitutions = null;
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList = [];
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void updateDietMeal(
    String day,
    String meal,
    int idx,
    String name,
    String qty,
  ) {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][meal] != null) {
      var currentMeals = List<dynamic>.from(_dietData![day][meal]);
      if (idx >= 0 && idx < currentMeals.length) {
        var oldItem = currentMeals[idx];
        currentMeals[idx] = {...oldItem, 'name': name, 'qty': qty};
        _dietData![day][meal] = currentMeals;
        _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
        _recalcAvailability();
        notifyListeners();
      }
    }
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }
}
