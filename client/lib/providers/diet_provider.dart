import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/diet_models.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../logic/diet_engine.dart';

import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../core/error_handler.dart';

class DietProvider extends ChangeNotifier {
  // Campi final non inizializzati inline (Dependency Injection)
  final DietRepository _repository;
  final StorageService _storage;
  final FirestoreService _firestore;
  final AuthService _auth;

  DietPlan? _dietPlan;
  List<PantryItem> _pantryItems = [];
  Map<String, ActiveSwap> _activeSwaps = {};

  Map<String, bool> _availabilityMap = {};
  List<String> _shoppingList = [];

  // Sync State
  DateTime _lastCloudSave = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastSyncedJson;
  static const Duration _cloudSaveInterval = Duration(minutes: 5);

  bool _isLoading = false;
  bool _isTranquilMode = false;
  String? _error;

  // Getters
  DietPlan? get dietPlan => _dietPlan;
  List<PantryItem> get pantryItems => _pantryItems;
  Map<String, ActiveSwap> get activeSwaps => _activeSwaps;
  Map<String, bool> get availabilityMap => _availabilityMap;
  List<String> get shoppingList => _shoppingList;

  bool get isLoading => _isLoading;
  bool get isTranquilMode => _isTranquilMode;
  String? get error => _error;
  bool get hasError => _error != null;

  Map<String, dynamic> get substitutions => _dietPlan?.substitutions ?? {};

  // --- CONSTRUCTOR INJECTION ---
  // Ora passiamo i servizi da fuori (Main -> Locator -> Provider)
  DietProvider({
    required DietRepository repository,
    required StorageService storage,
    required FirestoreService firestore,
    required AuthService auth,
  }) : _repository = repository,
       _storage = storage,
       _firestore = firestore,
       _auth = auth;

  // --- METHODS ---

  Future<bool> loadFromCache() async {
    bool hasData = false;
    try {
      _setLoading(true);

      final rawDiet = await _storage.loadDiet();
      _pantryItems = await _storage.loadPantry();
      _activeSwaps = await _storage.loadSwaps();

      if (rawDiet != null) {
        try {
          _dietPlan = DietPlan.fromJson(rawDiet);
          _lastSyncedJson = jsonEncode(_dietPlan!.toJson());
          _recalcAvailability();
          hasData = true;
        } catch (e) {
          debugPrint("⚠️ Errore Parsing Cache: $e");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Errore Cache Generale: $e");
    } finally {
      _setLoading(false);
    }
    notifyListeners();
    return hasData;
  }

  // ... (Il resto dei metodi rimane identico, usano _storage, _repository etc. che ora sono iniettati) ...

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
        if (data['plan'] != null || data['dietData'] != null) {
          final rawPlan =
              data['plan'] ??
              {
                'plan': data['dietData'],
                'substitutions': data['substitutions'],
              };
          final newPlan = DietPlan.fromJson(rawPlan);

          if (_lastSyncedJson != jsonEncode(newPlan.toJson())) {
            _dietPlan = newPlan;
            _activeSwaps = {};
            await _saveLocal();
            _lastSyncedJson = jsonEncode(_dietPlan!.toJson());
            _lastCloudSave = DateTime.now();
            _recalcAvailability();
            notifyListeners();
          }
        }
      }
    } catch (e) {
      debugPrint("⚠️ Sync Cloud fallito: $e");
    }
  }

  void loadHistoricalDiet(Map<String, dynamic> rawData) {
    try {
      _dietPlan = DietPlan.fromJson(rawData);
      _activeSwaps = {};
      _saveLocal();
      _recalcAvailability();
      notifyListeners();
    } catch (e) {
      _error = "Impossibile caricare questa versione storica.";
      notifyListeners();
    }
  }

  void toggleMealConsumed(String day, String mealName, int dishIndex) {
    if (_dietPlan == null) return;
    try {
      final daily = _dietPlan!.weeklyPlan[day];
      if (daily == null) return;
      final meal = daily.meals[mealName];
      if (meal == null || dishIndex >= meal.dishes.length) return;

      meal.dishes[dishIndex].isConsumed = !meal.dishes[dishIndex].isConsumed;

      _saveLocal();
      _tryCloudSync();
      _recalcAvailability();
      notifyListeners();
    } catch (e) {
      debugPrint("Errore toggle pasto: $e");
    }
  }

  void executeSwap(String day, String mealName, int cadCode, ActiveSwap swap) {
    final key = "${day}_${mealName}_$cadCode";
    _activeSwaps[key] = swap;
    _storage.saveSwaps(_activeSwaps);
    _recalcAvailability();
    notifyListeners();
  }

  void generateShoppingList(List<String> selectedDays) {
    if (_dietPlan == null) return;

    final requirements = DietEngine.calculateRequirements(
      plan: _dietPlan!,
      swaps: _activeSwaps,
    );

    List<String> resultList = [];
    final virtualPantry = _pantryToMap(_pantryItems);
    requirements.forEach((key, neededQty) {
      final parts = key.split('||');
      final name = parts[0];
      final unit = parts[1];
      double available = 0.0;
      for (var k in virtualPantry.keys) {
        if (k.startsWith(name)) {
          available = virtualPantry[k]!;
          break;
        }
      }
      if (available < neededQty) {
        double missing = neededQty - available;
        String qtyDisplay = missing % 1 == 0
            ? missing.toInt().toString()
            : missing.toStringAsFixed(1);
        resultList.add("${_capitalize(name)} ($qtyDisplay $unit)".trim());
      }
    });
    _shoppingList = resultList;
    notifyListeners();
  }

  void updateShoppingList(List<String> newList) {
    _shoppingList = newList;
    notifyListeners();
  }

  void addPantryItem(String name, double qty, String unit) {
    final cleanName = name.trim();
    final cleanUnit = unit.trim().toLowerCase();
    int idx = _pantryItems.indexWhere(
      (p) =>
          p.name.toLowerCase() == cleanName.toLowerCase() &&
          p.unit.toLowerCase() == cleanUnit,
    );
    if (idx >= 0) {
      _pantryItems[idx].quantity += qty;
    } else {
      _pantryItems.add(
        PantryItem(name: cleanName, quantity: qty, unit: cleanUnit),
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

  Future<int> scanReceipt(String path) async {
    _setLoading(true);
    clearError();
    int count = 0;
    try {
      final allowed = _extractAllowedFoods();
      final items = await _repository.scanReceipt(path, allowed);

      for (var item in items) {
        if (item is Map && item.containsKey('name')) {
          addPantryItem(
            item['name'],
            double.tryParse(item['quantity'].toString()) ?? 1.0,
            item['unit'] ?? 'pz',
          );
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

  Future<void> clearData() async {
    await _storage.clearAll();
    _dietPlan = null;
    _pantryItems = [];
    _activeSwaps = {};
    _shoppingList = [];
    notifyListeners();
  }

  void toggleTranquilMode() {
    _isTranquilMode = !_isTranquilMode;
    notifyListeners();
  }

  Future<void> uploadDiet(String path) async {
    _setLoading(true);
    _error = null;
    try {
      String? token;
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
      final result = await _repository.uploadDiet(path, fcmToken: token);
      _dietPlan = result;
      _activeSwaps = {};
      await _saveLocal();
      if (_auth.currentUser != null) {
        await _firestore.saveDietToHistory(
          _dietPlan!.toJson(),
          _dietPlan!.substitutions,
        );
        _lastCloudSave = DateTime.now();
        _lastSyncedJson = jsonEncode(_dietPlan!.toJson());
      }
      _recalcAvailability();
    } catch (e) {
      _error = ErrorMapper.toUserMessage(e);
      rethrow;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> _saveLocal() async {
    if (_dietPlan != null) {
      await _storage.saveDiet(_dietPlan!.toJson());
    }
  }

  Future<void> _tryCloudSync() async {
    if (_auth.currentUser == null || _dietPlan == null) return;

    final bool timePassed =
        DateTime.now().difference(_lastCloudSave) > _cloudSaveInterval;
    final String currentJson = jsonEncode(_dietPlan!.toJson());

    if (timePassed && currentJson != _lastSyncedJson) {
      try {
        await _firestore.saveDietToHistory(
          _dietPlan!.toJson(),
          _dietPlan!.substitutions,
        );
        _lastCloudSave = DateTime.now();
        _lastSyncedJson = currentJson;
      } catch (e) {
        debugPrint("Errore Cloud Sync: $e");
      }
    }
  }

  void _recalcAvailability() {
    if (_dietPlan == null) return;
    _availabilityMap = DietEngine.calculateAvailability(
      _dietPlan!,
      _pantryItems,
      _activeSwaps,
    );
    notifyListeners();
  }

  Map<String, double> _pantryToMap(List<PantryItem> items) {
    Map<String, double> m = {};
    for (var i in items) {
      m["${i.name.toLowerCase()}||${i.unit.toLowerCase()}"] = i.quantity;
    }
    return m;
  }

  List<String> _extractAllowedFoods() {
    if (_dietPlan == null) return [];
    Set<String> foods = {};
    _dietPlan!.weeklyPlan.forEach((_, daily) {
      daily.meals.forEach((_, meal) {
        for (var d in meal.dishes) {
          foods.add(d.name);
        }
      });
    });
    return foods.toList();
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
