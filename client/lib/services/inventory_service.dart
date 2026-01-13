import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import '../models/pantry_item.dart';

const String taskInventoryCheck = "inventoryCheck";

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == taskInventoryCheck) {
      final notifs = NotificationService();
      await notifs.init();

      final storage = StorageService();
      // MODIFICA: Carichiamo tutto il dizionario, non solo il piano
      final dietFull = await storage.loadDiet();
      final pantry = await storage.loadPantry();

      if (dietFull == null || dietFull['plan'] == null) {
        return Future.value(true);
      }

      final Map<String, dynamic> plan = dietFull['plan'];
      // MODIFICA: Recuperiamo le sostituzioni salvate
      final Map<String, dynamic> substitutions =
          dietFull['substitutions'] ?? {};

      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dayName = _getDayName(tomorrow.weekday);

      if (plan[dayName] != null) {
        // Passiamo anche le sostituzioni e il nome del giorno al checker
        bool missing = _checkMissingIngredients(
          plan[dayName],
          pantry,
          substitutions,
          dayName,
        );

        if (missing) {
          await notifs.flutterLocalNotificationsPlugin.show(
            999,
            "Occhio alla spesa! 🛒",
            "Ti mancano alcuni ingredienti per domani ($dayName).",
            const NotificationDetails(
              android: AndroidNotificationDetails(
                'inventory_channel',
                'Inventory Checks',
                channelDescription: 'Alerts for missing ingredients',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: DarwinNotificationDetails(),
            ),
          );
        }
      }
    }
    return Future.value(true);
  });
}

class InventoryService {
  static Future<void> initialize() async {
    try {
      await Workmanager().initialize(callbackDispatcher);

      if (Platform.isAndroid) {
        // --- CONFIGURAZIONE ANDROID ---
        await Workmanager().registerPeriodicTask(
          "1", // ID univoco per Android
          taskInventoryCheck, // Nome della funzione/task
          frequency: const Duration(hours: 24),
          constraints: Constraints(
            // [FIX 1] Usa snake_case per workmanager 0.9.0+
            networkType: NetworkType.notRequired,
          ),
        );
      } else if (Platform.isIOS) {
        // --- CONFIGURAZIONE IOS ---
        // Su iOS non esiste "PeriodicTask" preciso come su Android.
        // Usiamo OneOffTask che il sistema eseguirà quando possibile.
        // [FIX 2] L'ID e il Nome DEVONO essere "workmanager.background.task" (come in Info.plist)
        await Workmanager().registerOneOffTask(
          "workmanager.background.task", // ID (Match Info.plist)
          "workmanager.background.task", // Task Name (Match ID)
          constraints: Constraints(
            networkType: NetworkType.notRequired,
          ),
        );
      }
    } catch (e) {
      debugPrint("⚠️ Errore inizializzazione Workmanager: $e");
    }
  }
}

String _getDayName(int weekday) {
  const days = [
    "Lunedì",
    "Martedì",
    "Mercoledì",
    "Giovedì",
    "Venerdì",
    "Sabato",
    "Domenica",
  ];
  return days[weekday - 1];
}

bool _checkMissingIngredients(
  Map<String, dynamic> dayPlan,
  List<PantryItem> pantry,
  Map<String, dynamic> substitutions,
  String dayName,
) {
  // MODIFICA: Iteriamo su entries per avere il nome del pasto (Pranzo, Cena...)
  for (var entry in dayPlan.entries) {
    String mealName = entry.key;
    var mealContent = entry.value;

    if (mealContent is List) {
      for (var dish in mealContent) {
        // --- 1. Generazione Chiave Swap (Allineata al resto dell'App) ---
        String? instanceId = dish['instance_id']?.toString();
        int cadCode = dish['cad_code'] ?? 0;

        // Uso '::' come definito nel refactoring precedente
        String swapKey = (instanceId != null && instanceId.isNotEmpty)
            ? "$dayName::$mealName::$instanceId"
            : "$dayName::$mealName::$cadCode";

        List<dynamic> itemsToCheck = [];

        // --- 2. Controllo Swap ---
        if (substitutions.containsKey(swapKey)) {
          // Se swappato, controlliamo gli ingredienti sostitutivi
          var subData = substitutions[swapKey];
          if (subData != null && subData['swappedIngredients'] != null) {
            itemsToCheck = subData['swappedIngredients'];
          }
        } else {
          // Se NON swappato, controlliamo il piatto originale
          itemsToCheck = [dish];
        }

        // --- 3. Verifica Disponibilità ---
        for (var itemReq in itemsToCheck) {
          String reqName = itemReq['name'].toString().toLowerCase();

          if (reqName.contains("libero") || reqName.contains("avanzi")) {
            continue;
          }

          // Logica di match: cerchiamo se c'è qualcosa in dispensa > 0
          // (Manteniamo la logica semplice "contains" per ora, ma applicata all'ingrediente GIUSTO)
          bool found = pantry.any(
            (pItem) =>
                (pItem.name.toLowerCase().contains(reqName) ||
                    reqName.contains(pItem.name.toLowerCase())) &&
                pItem.quantity > 0.1,
          );

          if (!found) return true; // Appena manca qualcosa, scatta l'alert
        }
      }
    }
  }
  return false;
}
