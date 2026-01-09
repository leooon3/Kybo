import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../core/error_handler.dart';
import '../logic/diet_calculator.dart';

class DietProvider extends ChangeNotifier {
  final DietRepository _repository;
  final StorageService _storage = StorageService();
  final FirestoreService _firestore = FirestoreService();
  final AuthService _auth = AuthService();

  Map<String, dynamic>? _dietData;
  Map<String, dynamic>? _substitutions;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};
  List<String> _shoppingList = [];
  Map<String, bool> _availabilityMap = {};
  Map<String, double> _conversions = {};

  // Campi per il Sync Intelligente
  DateTime _lastCloudSave = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? _lastSyncedDiet;
  Map<String, dynamic>? _lastSyncedSubstitutions;
  static const Duration _cloudSaveInterval = Duration(hours: 3);

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

  DietProvider(this._repository);

  // --- INIT & SYNC ---

  Future<bool> loadFromCache() async {
    bool hasData = false;
    try {
      _setLoading(true);
      final savedDiet = await _storage.loadDiet();
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();
      _conversions = await _storage.loadConversions();

      if (savedDiet != null && savedDiet['plan'] != null) {
        _dietData = savedDiet['plan'];
        _substitutions = savedDiet['substitutions'];
        // Inizializza lo stato di sync
        _lastSyncedDiet = _deepCopy(_dietData);
        _lastSyncedSubstitutions = _deepCopy(_substitutions);
        _recalcAvailability();
        hasData = true;
      }
    } catch (e) {
      debugPrint("⚠️ Errore Cache: $e");
    } finally {
      _setLoading(false);
    }
    notifyListeners();
    return hasData;
  }

  Future<void> syncFromFirebase(String uid) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('history')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        if (data['dietData'] != null) {
          _dietData = data['dietData'];
          _substitutions = data['substitutions'];
          await _storage.saveDiet({
            'plan': _dietData,
            'substitutions': _substitutions,
          });

          // Aggiorna baseline sync
          _lastSyncedDiet = _deepCopy(_dietData);
          _lastSyncedSubstitutions = _deepCopy(_substitutions);
          _lastCloudSave = DateTime.now();

          _recalcAvailability();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Sync Cloud fallito: $e");
    }
  }

  void loadHistoricalDiet(Map<String, dynamic> dietData) {
    _dietData = dietData['plan'];
    _substitutions = dietData['substitutions'];
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _activeSwaps = {};
    _storage.saveSwaps({});

    // Reset sync baseline quando carico uno storico
    _lastSyncedDiet = _deepCopy(_dietData);
    _lastSyncedSubstitutions = _deepCopy(_substitutions);

    _recalcAvailability();
    notifyListeners();
  }

  Future<void> refreshAvailability() async {
    await _recalcAvailability();
  }

  // --- LOGICA CONSUMO & AGGIORNAMENTO ---

  void updateDietMeal(
    String day,
    String meal,
    int idx,
    String name,
    String qty,
  ) async {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][meal] != null) {
      var currentMeals = List<dynamic>.from(_dietData![day][meal]);
      if (idx >= 0 && idx < currentMeals.length) {
        var oldItem = currentMeals[idx];
        currentMeals[idx] = {...oldItem, 'name': name, 'qty': qty};
        _dietData![day][meal] = currentMeals;
        _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});

        // SYNC INTELLIGENTE: Usa i campi _lastSyncedDiet/Substitutions per evitare spam
        if (_auth.currentUser != null) {
          bool timePassed =
              DateTime.now().difference(_lastCloudSave) > _cloudSaveInterval;

          // Controlla se ci sono modifiche strutturali reali (ignorando 'consumed')
          bool isStructurallyDifferent =
              _hasStructuralChanges(_dietData, _lastSyncedDiet) ||
              jsonEncode(_substitutions) !=
                  jsonEncode(_lastSyncedSubstitutions);

          if (timePassed && isStructurallyDifferent) {
            await _firestore.saveDietToHistory(_dietData!, _substitutions!);
            _lastCloudSave = DateTime.now();
            _lastSyncedDiet = _deepCopy(_dietData);
            _lastSyncedSubstitutions = _deepCopy(_substitutions);
            debugPrint("☁️ Cloud Sync Eseguito (Modifiche rilevate)");
          }
        }

        _recalcAvailability();
        notifyListeners();
      }
    }
  }

  Future<void> consumeMeal(
    String day,
    String mealType,
    int dishIndex, {
    bool force = false,
  }) async {
    if (_dietData == null || _dietData![day] == null) return;
    final meals = _dietData![day][mealType];
    if (meals == null || meals is! List || dishIndex >= meals.length) return;

    List<List<int>> groups = DietCalculator.buildGroups(meals);
    List<int> targetGroupIndices = [];

    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(dishIndex)) {
        targetGroupIndices = groups[g];
        break;
      }
    }
    if (targetGroupIndices.isEmpty) return;

    // FASE 1: Validazione
    if (!force) {
      for (int i in targetGroupIndices) {
        _processItem(
          meals[i],
          day,
          mealType,
          (name, qty) => _validateItem(name, qty),
        );
      }
    }

    // FASE 2: Esecuzione
    for (int i in targetGroupIndices) {
      _processItem(
        meals[i],
        day,
        mealType,
        (name, qty) => _consumeExecute(name, qty),
      );
    }

    // FASE 3: Aggiorna UI
    var currentMealsList = List<dynamic>.from(_dietData![day][mealType]);
    for (int i in targetGroupIndices) {
      if (i < currentMealsList.length) {
        var item = Map<String, dynamic>.from(currentMealsList[i]);
        item['consumed'] = true;
        currentMealsList[i] = item;
      }
    }

    _dietData![day][mealType] = currentMealsList;
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _recalcAvailability();
    notifyListeners();
  }

  // --- HELPER METODS ---

  void _processItem(
    dynamic dish,
    String day,
    String mealType,
    Function(String, String) action,
  ) {
    final String? instanceId = dish['instance_id']?.toString();
    final int cadCode = dish['cad_code'] ?? 0;

    String swapKey = (instanceId != null && instanceId.isNotEmpty)
        ? "${day}_${mealType}_$instanceId"
        : "${day}_${mealType}_$cadCode";

    if (_activeSwaps.containsKey(swapKey)) {
      final activeSwap = _activeSwaps[swapKey]!;
      final List<dynamic> swapIngs = activeSwap.swappedIngredients ?? [];
      if (swapIngs.isNotEmpty) {
        for (var ing in swapIngs) {
          action(ing['name'].toString(), ing['qty'].toString());
        }
      } else {
        action(activeSwap.name, "${activeSwap.qty} ${activeSwap.unit}");
      }
    } else {
      List<dynamic> itemsToCheck = [];
      String qtyStr = dish['qty']?.toString() ?? "";
      if (qtyStr == "N/A" ||
          (dish['ingredients'] != null &&
              (dish['ingredients'] as List).isNotEmpty)) {
        itemsToCheck = dish['ingredients'] ?? [];
      } else {
        itemsToCheck = [
          {'name': dish['name'], 'qty': qtyStr.isEmpty ? '1' : qtyStr},
        ];
      }
      for (var itemData in itemsToCheck) {
        action(itemData['name'].toString(), itemData['qty'].toString());
      }
    }
  }

  void _validateItem(String name, String rawQtyString) {
    if (rawQtyString == "N/A" || name.toLowerCase().contains("libero")) return;

    double reqQty = DietCalculator.parseQty(rawQtyString);
    String reqUnit = DietCalculator.parseUnit(rawQtyString, name);
    String normalizedName = name.trim().toLowerCase();

    int index = _pantryItems.indexWhere((p) {
      final pName = p.name.toLowerCase();
      return (pName == normalizedName ||
          pName.contains(normalizedName) ||
          normalizedName.contains(pName));
    });

    if (index == -1) {
      throw IngredientException("Prodotto non trovato in dispensa: $name");
    }

    PantryItem pItem = _pantryItems[index];

    if (pItem.unit.trim().toLowerCase() == reqUnit.trim().toLowerCase()) {
      if (pItem.quantity < reqQty) {
        throw IngredientException(
          "Quantità insufficiente di $name. Hai ${pItem.quantity} ${pItem.unit}, servono $reqQty.",
        );
      }
      return;
    }

    double conversionFactor = 1.0;
    String convKey =
        "${normalizedName}_${reqUnit.trim().toLowerCase()}_to_${pItem.unit.trim().toLowerCase()}";

    if (_conversions.containsKey(convKey)) {
      conversionFactor = _conversions[convKey]!;
    } else {
      double pVal = DietCalculator.normalizeToGrams(1, pItem.unit);
      double rVal = DietCalculator.normalizeToGrams(1, reqUnit);
      if (pVal <= 0 || rVal <= 0) {
        throw UnitMismatchException(item: pItem, requiredUnit: reqUnit);
      }
    }

    double reqQtyInPantryUnit = reqQty;
    if (_conversions.containsKey(convKey)) {
      reqQtyInPantryUnit = reqQty * conversionFactor;
    } else {
      double rGrams = DietCalculator.normalizeToGrams(reqQty, reqUnit);
      double pGrams = DietCalculator.normalizeToGrams(1, pItem.unit);
      if (pGrams > 0) reqQtyInPantryUnit = rGrams / pGrams;
    }

    if (pItem.quantity < reqQtyInPantryUnit) {
      throw IngredientException("Quantità insufficiente di $name.");
    }
  }

  void _consumeExecute(String name, String rawQtyString) {
    if (rawQtyString == "N/A") return;
    double reqQty = DietCalculator.parseQty(rawQtyString);
    String reqUnit = DietCalculator.parseUnit(rawQtyString, name);
    String normalizedName = name.trim().toLowerCase();

    int index = _pantryItems.indexWhere((p) {
      final pName = p.name.toLowerCase();
      return (pName.contains(normalizedName) || normalizedName.contains(pName));
    });

    if (index != -1) {
      var item = _pantryItems[index];
      double qtyToSubtract = reqQty;

      if (item.unit.toLowerCase() != reqUnit.toLowerCase()) {
        String convKey =
            "${normalizedName}_${reqUnit.trim().toLowerCase()}_to_${item.unit.trim().toLowerCase()}";
        if (_conversions.containsKey(convKey)) {
          qtyToSubtract = reqQty * _conversions[convKey]!;
        } else {
          double rGrams = DietCalculator.normalizeToGrams(reqQty, reqUnit);
          double pGramsOne = DietCalculator.normalizeToGrams(1, item.unit);
          if (rGrams > 0 && pGramsOne > 0) qtyToSubtract = rGrams / pGramsOne;
        }
      }

      item.quantity -= qtyToSubtract;
      if (item.quantity <= 0.01) {
        _pantryItems.removeAt(index);
      }
      _storage.savePantry(_pantryItems);
    }
  }

  Future<void> resolveUnitMismatch(
    String itemName,
    String fromUnit,
    String toUnit,
    double factor,
  ) async {
    final key =
        "${itemName.trim().toLowerCase()}_${fromUnit.trim().toLowerCase()}_to_${toUnit.trim().toLowerCase()}";
    _conversions[key] = factor;
    await _storage.saveConversions(_conversions);
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    clearError();
    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
      final result = await _repository.uploadDiet(path, fcmToken: token);
      _dietData = result.plan;
      _substitutions = result.substitutions;
      await _storage.saveDiet({
        'plan': _dietData,
        'substitutions': _substitutions,
      });
      if (_auth.currentUser != null) {
        await _firestore.saveDietToHistory(_dietData!, _substitutions!);
        _lastCloudSave = DateTime.now();
        _lastSyncedDiet = _deepCopy(_dietData);
        _lastSyncedSubstitutions = _deepCopy(_substitutions);
      }
      _activeSwaps = {};
      await _storage.saveSwaps({});
      _recalcAvailability();
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
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
      final items = await _repository.scanReceipt(path, _extractAllowedFoods());
      for (var item in items) {
        if (item is Map && item.containsKey('name')) {
          String rawQty = item['quantity']?.toString() ?? "1";
          double qty = DietCalculator.parseQty(rawQty);
          String unit = DietCalculator.parseUnit(rawQty, item['name']);
          if (rawQty.toLowerCase().contains('l') &&
              !rawQty.toLowerCase().contains('ml')) {
            qty *= 1000;
          }
          if (rawQty.toLowerCase().contains('kg')) qty *= 1000;
          addPantryItem(item['name'], qty, unit);
          count++;
        }
      }
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
    return count;
  }

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

  void removePantryItem(int index) {
    if (index >= 0 && index < _pantryItems.length) {
      _pantryItems.removeAt(index);
      _storage.savePantry(_pantryItems);
      _recalcAvailability();
      notifyListeners();
    }
  }

  Future<void> _recalcAvailability() async {
    if (_dietData == null) return;
    final payload = {
      'dietData': _dietData,
      'pantryItems': _pantryItems
          .map((p) => {'name': p.name, 'quantity': p.quantity, 'unit': p.unit})
          .toList(),
      'activeSwaps': _activeSwaps.map(
        (key, value) => MapEntry(key, {
          'name': value.name,
          'qty': value.qty,
          'unit': value.unit,
          'swappedIngredients': value.swappedIngredients,
        }),
      ),
    };
    try {
      final newMap = await compute(
        DietCalculator.calculateAvailabilityIsolate,
        payload,
      );
      _availabilityMap = newMap;
      notifyListeners();
    } catch (e) {
      debugPrint("Isolate Calc Error: $e");
    }
  }

  // --- UTILS & HELPERS ---

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

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  void updateShoppingList(List<String> list) {
    _shoppingList = list;
    notifyListeners();
  }

  void swapMeal(String key, ActiveSwap swap) {
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }

  void consumeSmart(String name, String qty) {
    try {
      _validateItem(name, qty);
      _consumeExecute(name, qty);
      notifyListeners();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> clearData() async {
    await _storage.clearAll();
    _dietData = null;
    _substitutions = null;
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList = [];
    _conversions = {};
    notifyListeners();
  }

  // Deep copy e Helpers per il Sync differenziale
  Map<String, dynamic>? _deepCopy(Map<String, dynamic>? input) {
    if (input == null) return null;
    return jsonDecode(jsonEncode(input));
  }

  bool _hasStructuralChanges(
    Map<String, dynamic>? current,
    Map<String, dynamic>? old,
  ) {
    if (current == null && old == null) return false;
    if (current == null || old == null) return true;
    String sCurrent = jsonEncode(_sanitize(current));
    String sOld = jsonEncode(_sanitize(old));
    return sCurrent != sOld;
  }

  // Rimuove campi volatili (consumed) per confrontare solo la struttura
  dynamic _sanitize(dynamic input) {
    if (input is Map) {
      final newMap = <String, dynamic>{};
      input.forEach((key, value) {
        if (key != 'consumed' && key != 'cad_code') {
          newMap[key.toString()] = _sanitize(value);
        }
      });
      return newMap;
    } else if (input is List) {
      return input.map((e) => _sanitize(e)).toList();
    }
    return input;
  }
}
