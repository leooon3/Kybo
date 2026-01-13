import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kybo/logic/diet_logic.dart';
import '../repositories/diet_repository.dart';
import '../services/storage_service.dart';
import '../services/firestore_service.dart';
import '../services/auth_service.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';
import '../core/error_handler.dart';
import '../logic/diet_calculator.dart';
import 'package:permission_handler/permission_handler.dart'; // <--- NUOVO
import '../services/notification_service.dart'; // <--- NUOVO (se non c'è già)

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
  final NotificationService _notificationService =
      NotificationService(); // Servizio notifiche

  bool _needsNotificationPermissions = false;
  bool get needsNotificationPermissions => _needsNotificationPermissions;

  void resetPermissionFlag() {
    _needsNotificationPermissions = false;
    // Non chiamiamo notifyListeners() qui per evitare loop di rebuild
  }

  // [NUOVO] Logica di Sync Intelligente
  Future<String> runSmartSyncCheck({bool forceSync = false}) async {
    final user = _auth.currentUser;
    if (user == null || _dietData == null) return "Errore: Dati mancanti.";

    // 1. Controllo Modifiche
    bool hasSwapsChanged = _activeSwaps.isNotEmpty;
    bool hasChanges =
        _hasStructuralChanges(_dietData, _lastSyncedDiet) || hasSwapsChanged;

    if (!hasChanges && !forceSync) {
      return "✅ Nessuna modifica da salvare.";
    }

    // 2. Controllo Tempo (3h)
    final now = DateTime.now();
    final difference = now.difference(_lastCloudSave);

    if (!forceSync && difference.inHours < 3) {
      return "⏳ Modifiche in coda (attesa 3h).";
    }

    // [CORREZIONE] Serializzazione corretta usando la tua classe
    final Map<String, dynamic> swapsToSave = {};
    _activeSwaps.forEach((key, value) {
      swapsToSave[key] = value.toMap(); // Usa il tuo metodo
    });

    try {
      if (_currentFirestoreId == null) {
        // CREAZIONE
        String newId = await _firestore.saveDietToHistory(
          _sanitize(_dietData!),
          _sanitize(_substitutions ?? {}),
          swapsToSave, // <--- INVIO MAPPA CORRETTA
        );
        _currentFirestoreId = newId;
        _lastCloudSave = now;
        _lastSyncedDiet = _deepCopy(_dietData);
        return "🆕 Nuova Dieta Salvata (ID: $newId).";
      } else {
        // AGGIORNAMENTO
        await _firestore.updateDietHistory(
          _currentFirestoreId!,
          _sanitize(_dietData!),
          _sanitize(_substitutions ?? {}),
          swapsToSave, // <--- INVIO MAPPA CORRETTA
        );
        _lastCloudSave = now;
        _lastSyncedDiet = _deepCopy(_dietData);
        return "☁️ Dieta Aggiornata con le tue modifiche.";
      }
    } catch (e) {
      return "❌ Errore Sync: $e";
    }
  }

  // Getters
  Map<String, dynamic>? get dietData => _dietData;
  Map<String, dynamic>? get substitutions => _substitutions;
  String? _currentFirestoreId;
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
      // MODIFICA: Leggiamo da 'diets/current' invece che cercare l'ultimo in 'history'
      final docSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('diets') // Corretto: ora corrisponde a FirestoreService
          .doc('current') // Corretto: puntiamo al file unico
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        if (data != null && data['plan'] != null) {
          // Qui dovremmo implementare la logica di Merge Intelligente
          // per non sovrascrivere i 'consumed' locali se il cloud è più vecchio o uguale.
          // Per ora, carichiamo i dati strutturali.

          _dietData = data['plan'];
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

          await _scheduleMealNotifications();
          notifyListeners();
          debugPrint("☁️ Sync Cloud completato (da 'current')");
        }
      }
    } catch (e) {
      debugPrint("⚠️ Sync Cloud fallito: $e");
    }
  }

  void loadHistoricalDiet(Map<String, dynamic> dietData, String docId) {
    debugPrint("📂 Caricamento dieta ID: $docId");

    _dietData = dietData['plan'];
    _substitutions = dietData['substitutions'];
    _currentFirestoreId = docId;

    // [CORREZIONE] Ripristino usando la tua classe ActiveSwap
    _activeSwaps = {};

    if (dietData['activeSwaps'] != null) {
      try {
        final rawSwaps = dietData['activeSwaps'] as Map;

        rawSwaps.forEach((key, value) {
          if (value is Map) {
            // Qui ricostruiamo l'oggetto usando i tuoi campi (name, qty, unit)
            // La chiave (es. "Lunedi_Pranzo_0") ci dice dove posizionarlo
            final swapObj =
                ActiveSwap.fromMap(Map<String, dynamic>.from(value));
            _activeSwaps[key.toString()] = swapObj;
          }
        });
        debugPrint("✅ Ripristinati ${_activeSwaps.length} scambi attivi.");
      } catch (e) {
        debugPrint("⚠️ Errore critico ripristino swap: $e");
      }
    }

    // Persistenza Locale e UI
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});
    _storage.saveSwaps(_activeSwaps);

    _lastSyncedDiet = _deepCopy(_dietData);
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
    int unsafeIndex, // Rinominiamo per chiarezza: è un indice "insicuro"
    String name,
    String qty, {
    String? instanceId, // NUOVO: Identificativo univoco
    int? cadCode, // NUOVO: Identificativo legacy
  }) async {
    if (_dietData != null &&
        _dietData![day] != null &&
        _dietData![day][meal] != null) {
      var currentMeals = List<dynamic>.from(_dietData![day][meal]);

      // [FIX STABILITÀ] Cerchiamo l'indice reale basandoci sugli ID
      int realIndex = unsafeIndex;

      if (instanceId != null || cadCode != null) {
        final foundIndex = currentMeals.indexWhere((m) {
          final mId = m['instance_id']?.toString();
          final mCode = m['cad_code'];
          // Controllo robusto: Priorità a instanceId, fallback a cadCode
          if (instanceId != null && mId == instanceId) return true;
          if (cadCode != null && mCode == cadCode) return true;
          return false;
        });

        if (foundIndex != -1) {
          realIndex = foundIndex;
        } else {
          debugPrint(
            "⚠️ Update annullato: Piatto non trovato (Sync mismatch?)",
          );
          return; // Ci fermiamo per evitare corruzione dati
        }
      }

      // Procedi solo se l'indice è valido
      if (realIndex >= 0 && realIndex < currentMeals.length) {
        var oldItem = currentMeals[realIndex];
        currentMeals[realIndex] = {...oldItem, 'name': name, 'qty': qty};
        _dietData![day][meal] = currentMeals;

        // Salvataggio locale
        _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});

        // Logica Sync Intelligente (Invariata)
        if (_auth.currentUser != null) {
          bool timePassed =
              DateTime.now().difference(_lastCloudSave) > _cloudSaveInterval;
          bool isStructurallyDifferent =
              _hasStructuralChanges(_dietData, _lastSyncedDiet) ||
                  jsonEncode(_substitutions) !=
                      jsonEncode(_lastSyncedSubstitutions);

          if (timePassed && isStructurallyDifferent) {
            // 1. Convertiamo gli swap attivi in mappa
            final Map<String, dynamic> currentSwaps = {};
            _activeSwaps.forEach((key, value) {
              currentSwaps[key] = value.toMap();
            });

// 2. Salviamo tutto
            await _firestore.saveDietToHistory(
              _sanitize(_dietData!),
              _sanitize(_substitutions ?? {}),
              currentSwaps, // <--- TERZO ARGOMENTO: Passiamo gli swap attivi
            );
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

  // [REFACTORING 4.1] Logica delegata a DietLogic

  Future<void> consumeMeal(
    String day,
    String mealType,
    int unsafeIndex, {
    bool force = false,
    String? instanceId,
    int? cadCode,
  }) async {
    if (_dietData == null || _dietData![day] == null) return;
    final meals = _dietData![day][mealType];
    if (meals == null || meals is! List) return;

    // 1. Risoluzione Indice
    int realIndex = unsafeIndex;
    if (instanceId != null || cadCode != null) {
      final foundIndex = meals.indexWhere((m) {
        final mId = m['instance_id']?.toString();
        final mCode = m['cad_code'];
        if (instanceId != null && mId == instanceId) return true;
        if (cadCode != null && mCode == cadCode) return true;
        return false;
      });
      if (foundIndex != -1) realIndex = foundIndex;
    }

    if (realIndex >= meals.length) return;

    // 2. Identificazione Gruppo (con Fallback di sicurezza)
    List<List<int>> groups = DietCalculator.buildGroups(meals);
    List<int> targetGroupIndices = [];
    for (int g = 0; g < groups.length; g++) {
      if (groups[g].contains(realIndex)) {
        targetGroupIndices = groups[g];
        break;
      }
    }
    // FALLBACK: Se il gruppo fallisce, consumiamo almeno il piatto singolo
    if (targetGroupIndices.isEmpty) targetGroupIndices = [realIndex];

    // 3. Preparazione Ingredienti
    List<Map<String, String>> allIngredientsToProcess = [];
    for (int i in targetGroupIndices) {
      var dish = meals[i];
      var ingredients = DietLogic.resolveIngredients(
        dish: dish,
        day: day,
        mealType: mealType,
        activeSwaps: _activeSwaps,
      );
      allIngredientsToProcess.addAll(ingredients);
    }

    // 4. Validazione
    if (!force) {
      for (var ing in allIngredientsToProcess) {
        DietLogic.validateItem(
          name: ing['name']!,
          rawQtyString: ing['qty']!,
          pantryItems: _pantryItems,
          conversions: _conversions,
        );
      }
    }

    // 5. Esecuzione Consumo Dispensa
    bool pantryModified = false;
    for (var ing in allIngredientsToProcess) {
      bool changed = DietLogic.consumeItem(
        name: ing['name']!,
        rawQtyString: ing['qty']!,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );
      if (changed) pantryModified = true;
    }

    if (pantryModified) {
      _storage.savePantry(_pantryItems);
    }

    // 6. MARCATURA CONSUMATO (Fix Robusto)
    var currentMealsList = List<dynamic>.from(_dietData![day][mealType]);
    for (int i in targetGroupIndices) {
      if (i < currentMealsList.length) {
        var item = Map<String, dynamic>.from(currentMealsList[i]);
        item['consumed'] = true; // Impostiamo esplicitamente true boolean
        currentMealsList[i] = item;
        debugPrint("✅ Piatto segnato consumato: ${item['name']}");
      }
    }

    _dietData![day][mealType] = currentMealsList;
    _storage.saveDiet({'plan': _dietData, 'substitutions': _substitutions});

    // 7. SINCRONIZZAZIONE (Cruciale: await)
    // Attendiamo che il calcolo dispensa finisca.
    // _recalcAvailability ora aggiornerà anche la lista della spesa.
    await _recalcAvailability();

    // Non serve notifyListeners() qui perché lo chiama _recalcAvailability
  }

  // Anche consumeSmart diventa un wrapper one-line
  void consumeSmart(String name, String qty) {
    try {
      DietLogic.validateItem(
        name: name,
        rawQtyString: qty,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );

      bool changed = DietLogic.consumeItem(
        name: name,
        rawQtyString: qty,
        pantryItems: _pantryItems,
        conversions: _conversions,
      );

      if (changed) {
        _storage.savePantry(_pantryItems);
        notifyListeners();
      }
    } catch (e) {
      rethrow;
    }
  }

  // --- HELPER METODS ---
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
        await _firestore.saveDietToHistory(
          _sanitize(_dietData!),
          _sanitize(_substitutions ?? {}),
          {}, // <--- TERZO ARGOMENTO: Nessuno swap attivo all'inizio
        );
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

    // Preparazione Payload
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
      // Calcolo Disponibilità (Isolate)
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

  // FIX 2.3: Generazione Lista Spesa Centralizzata (Swap Aware)
  List<String> generateSmartShoppingList() {
    if (_dietData == null) return [];

    final Map<String, double> totals = {};
    // Ordine Giorni Fisso
    final days = [
      "Lunedì",
      "Martedì",
      "Mercoledì",
      "Giovedì",
      "Venerdì",
      "Sabato",
      "Domenica",
    ];

    for (var day in days) {
      if (!_dietData!.containsKey(day)) continue;
      final meals = _dietData![day];
      if (meals is! Map) continue;

      meals.forEach((mealType, dishes) {
        if (dishes is! List) return;

        for (int i = 0; i < dishes.length; i++) {
          var dish = dishes[i];

          // CONTROLLO 1: È stato mangiato? (Logica robusta per SQLite/JSON)
          var c = dish['consumed'];
          bool isConsumed = c == true ||
              c.toString().toLowerCase() == 'true' ||
              c == 1 ||
              c.toString() == '1';
          if (isConsumed) continue;

          // CONTROLLO 2: Ce l'ho già in dispensa?
          // Usiamo la mappa di disponibilità calcolata. Se è true (Verde), non serve comprare.
          String availKey = "${day}_${mealType}_$i";
          if (_availabilityMap.containsKey(availKey) &&
              _availabilityMap[availKey] == true) {
            continue;
          }

          // Se arrivo qui: Non l'ho mangiato E non ho gli ingredienti -> AGGIUNGI ALLA LISTA

          // Logica Swap
          final String? instanceId = dish['instance_id']?.toString();
          final int cadCode = dish['cad_code'] ?? 0;
          String swapKey = (instanceId != null && instanceId.isNotEmpty)
              ? "${day}_${mealType}_$instanceId"
              : "${day}_${mealType}_$cadCode";

          List<dynamic> itemsToProcess = [];

          if (_activeSwaps.containsKey(swapKey)) {
            final swap = _activeSwaps[swapKey]!;
            if (swap.swappedIngredients != null &&
                swap.swappedIngredients!.isNotEmpty) {
              itemsToProcess = swap.swappedIngredients!;
            } else {
              itemsToProcess = [
                {'name': swap.name, 'qty': "${swap.qty} ${swap.unit}"},
              ];
            }
          } else {
            if (dish['qty'] == 'N/A') continue; // Header
            if (dish['ingredients'] != null &&
                (dish['ingredients'] as List).isNotEmpty) {
              itemsToProcess = dish['ingredients'];
            } else {
              itemsToProcess = [
                {'name': dish['name'], 'qty': dish['qty']},
              ];
            }
          }

          for (var item in itemsToProcess) {
            String name = item['name'].toString().trim();
            if (name.toLowerCase().contains("libero")) continue;
            String entry = "$name (${item['qty']})";
            totals[entry] = (totals[entry] ?? 0) + 1;
          }
        }
      });
    }

    return totals.keys.toList();
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

  Future<void> _scheduleMealNotifications() async {
    if (_dietData == null) return;

    var status = await Permission.notification.status;

    if (status.isGranted) {
      // Abbiamo i permessi: pianifichiamo silenziosamente
      await _notificationService.scheduleDietNotifications(_dietData!);
      debugPrint("🔔 Notifiche pianificate con successo");
    } else {
      // Mancano i permessi: segnaliamo alla UI di chiedere aiuto all'utente
      _needsNotificationPermissions = true;
      notifyListeners();
    }
  }
}
