import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/pantry_item.dart';
import '../models/active_swap.dart';

class StorageService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>?> loadDiet() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonString = prefs.getString('diet_plan');
      if (jsonString == null) return null;
      return jsonDecode(jsonString);
    } catch (e) {
      debugPrint("⚠️ Errore caricamento dieta (corrotta?): $e");
      return null;
    }
  }

  Future<void> saveDiet(Map<String, dynamic> dietData) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('diet_plan', jsonEncode(dietData));
  }

  Future<List<PantryItem>> loadPantry() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonString = prefs.getString('pantry');
      if (jsonString == null) return [];
      List<dynamic> list = jsonDecode(jsonString);
      return list.map((e) => PantryItem.fromJson(e)).toList();
    } catch (e) {
      debugPrint("⚠️ Errore caricamento dispensa: $e");
      return [];
    }
  }

  Future<void> savePantry(List<PantryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'pantry',
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  Future<Map<String, ActiveSwap>> loadSwaps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? jsonString = prefs.getString('active_swaps');
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
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = swaps.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString('active_swaps', jsonEncode(jsonMap));
  }

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

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _storage.deleteAll();
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
}
