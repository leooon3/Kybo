import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class StorageService {
  // Configurazione per la massima sicurezza su Android e iOS
  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences:
          true, // Usa il chip di sicurezza hardware se disponibile
    ),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  // --- SENSITIVE DATA (Secure Storage + Migration Logic) ---

  Future<Map<String, dynamic>?> loadDiet() async {
    try {
      // 1. Prova a leggere dallo storage cifrato
      String? jsonString = await _secureStorage.read(key: 'diet_plan');

      // 2. MIGRATION CHECK: Se non c'è, controlla se esiste nella vecchia versione (in chiaro)
      if (jsonString == null) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('diet_plan')) {
          debugPrint("🔐 Migrazione Dieta: Spostamento in Secure Storage...");
          jsonString = prefs.getString('diet_plan');

          // Migra e pulisci
          if (jsonString != null) {
            await _secureStorage.write(key: 'diet_plan', value: jsonString);
            await prefs.remove('diet_plan');
          }
        }
      }

      if (jsonString == null) return null;
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint("⚠️ Errore caricamento dieta: $e");
      return null;
    }
  }

  Future<void> saveDiet(Map<String, dynamic> dietData) async {
    await _secureStorage.write(key: 'diet_plan', value: jsonEncode(dietData));
  }

  Future<List<PantryItem>> loadPantry() async {
    try {
      // 1. Secure Read
      String? jsonString = await _secureStorage.read(key: 'pantry');

      // 2. Migration Check
      if (jsonString == null) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('pantry')) {
          debugPrint(
            "🔐 Migrazione Dispensa: Spostamento in Secure Storage...",
          );
          jsonString = prefs.getString('pantry');
          if (jsonString != null) {
            await _secureStorage.write(key: 'pantry', value: jsonString);
            await prefs.remove('pantry');
          }
        }
      }

      if (jsonString == null) return [];
      List<dynamic> list = jsonDecode(jsonString);
      return list.map((e) => PantryItem.fromJson(e)).toList();
    } catch (e) {
      debugPrint("⚠️ Errore caricamento dispensa: $e");
      return [];
    }
  }

  Future<void> savePantry(List<PantryItem> items) async {
    await _secureStorage.write(
      key: 'pantry',
      value: jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, ActiveSwap>> loadSwaps() async {
    try {
      // 1. Secure Read
      String? jsonString = await _secureStorage.read(key: 'active_swaps');

      // 2. Migration Check
      if (jsonString == null) {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('active_swaps')) {
          debugPrint("🔐 Migrazione Swaps: Spostamento in Secure Storage...");
          jsonString = prefs.getString('active_swaps');
          if (jsonString != null) {
            await _secureStorage.write(key: 'active_swaps', value: jsonString);
            await prefs.remove('active_swaps');
          }
        }
      }

      if (jsonString == null) return {};
      Map<String, dynamic> jsonMap = jsonDecode(jsonString);
      return jsonMap.map(
        (key, value) => MapEntry(key, ActiveSwap.fromJson(value)),
      );
    } catch (e) {
      return {};
    }
  }

  Future<void> saveSwaps(Map<String, ActiveSwap> swaps) async {
    final jsonMap = swaps.map((key, value) => MapEntry(key, value.toJson()));
    await _secureStorage.write(key: 'active_swaps', value: jsonEncode(jsonMap));
  }

  // --- NON-SENSITIVE DATA (SharedPreferences - Performance Focus) ---

  Future<List<Map<String, dynamic>>> loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? raw = prefs.getString('custom_alarms');
      if (raw == null) return [];
      List<dynamic> list = jsonDecode(raw);
      return List<Map<String, dynamic>>.from(list);
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAlarms(List<Map<String, dynamic>> alarms) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_alarms', jsonEncode(alarms));
  }

  Future<Map<String, double>> loadConversions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString('custom_conversions');
    if (raw == null) return {};
    try {
      Map<String, dynamic> jsonMap = jsonDecode(raw);
      return jsonMap.map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (e) {
      return {};
    }
  }

  Future<void> saveConversions(Map<String, double> conversions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_conversions', jsonEncode(conversions));
  }

  // --- CLEANUP ---

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Pulisce le config
    await _secureStorage.deleteAll(); // Pulisce i dati sensibili
  }
}
