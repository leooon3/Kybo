import 'package:kybo/models/pantry_item.dart'; // Assicurati che l'import sia corretto per il tuo progetto

// --- ECCEZIONI DI DOMINIO ---
class UnitMismatchException implements Exception {
  final PantryItem item;
  final String requiredUnit;
  UnitMismatchException({required this.item, required this.requiredUnit});
  @override
  String toString() => "Unità diverse: ${item.unit} vs $requiredUnit";
}

class IngredientException implements Exception {
  final String message;
  IngredientException(this.message);
  @override
  String toString() => message;
}

// --- LOGICA PURA & PARSING ---
class DietCalculator {
  // Funzione Isolate (Top-level o static)
  static Map<String, bool> calculateAvailabilityIsolate(
    Map<String, dynamic> payload,
  ) {
    final dietData = payload['dietData'] as Map<String, dynamic>;
    final pantryItemsRaw = payload['pantryItems'] as List<dynamic>;
    final activeSwapsRaw = payload['activeSwaps'] as Map<String, dynamic>;

    Map<String, double> simulatedFridge = {};
    for (var item in pantryItemsRaw) {
      String iName = item['name'].toString().trim().toLowerCase();
      double iQty = double.tryParse(item['quantity'].toString()) ?? 0.0;
      String iUnit = item['unit'].toString().toLowerCase();

      if (iUnit == 'kg' || iUnit == 'l') iQty *= 1000;
      if (iUnit == 'gr') iUnit = 'g';
      simulatedFridge[iName] = iQty;
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
      if (d < todayIndex) continue; // Ottimizzazione: salta giorni passati
      String day = italianDays[d];
      if (!dietData.containsKey(day)) continue;

      final mealsOfDay = dietData[day] as Map<String, dynamic>;
      final mealTypes = [
        "Colazione",
        "Seconda Colazione",
        "Spuntino",
        "Pranzo",
        "Merenda",
        "Cena",
        "Spuntino Serale",
        "Nell'Arco Della Giornata",
      ];

      for (var mType in mealTypes) {
        if (!mealsOfDay.containsKey(mType)) continue;
        List<dynamic> dishes = List.from(mealsOfDay[mType]);
        List<List<int>> groups = buildGroups(dishes);

        for (int gIdx = 0; gIdx < groups.length; gIdx++) {
          List<int> indices = groups[gIdx];
          if (indices.isEmpty) continue;

          bool isConsumed = false;
          if (indices.isNotEmpty && dishes[indices[0]]['consumed'] == true) {
            isConsumed = true;
          }

          if (isConsumed) {
            for (int originalIdx in indices) {
              newMap["${day}_${mType}_$originalIdx"] = false;
            }
            continue;
          }

          final firstDish = dishes[indices[0]];
          final String? instanceId = firstDish['instance_id']?.toString();
          final int cadCode = firstDish['cad_code'] ?? 0;

          // Chiave Swap (Priorità a instanceId nuovo backend)
          String swapKey = (instanceId != null && instanceId.isNotEmpty)
              ? "${day}_${mType}_$instanceId"
              : "${day}_${mType}_$cadCode";

          bool isSwapped = activeSwapsRaw.containsKey(swapKey);

          if (isSwapped) {
            final swapData = activeSwapsRaw[swapKey];
            List<dynamic> swapItems = [];
            if (swapData['swappedIngredients'] != null &&
                (swapData['swappedIngredients'] as List).isNotEmpty) {
              swapItems = swapData['swappedIngredients'];
            } else {
              swapItems = [
                {
                  'name': swapData['name'],
                  'qty': "${swapData['qty']} ${swapData['unit']}",
                },
              ];
            }

            bool groupCovered = true;
            for (var item in swapItems) {
              if (!_checkAndConsumeSimulated(item, simulatedFridge)) {
                groupCovered = false;
              }
            }
            for (int originalIdx in indices) {
              newMap["${day}_${mType}_$originalIdx"] = groupCovered;
            }
          } else {
            for (int i in indices) {
              final dish = dishes[i];
              bool isCovered = true;
              if ((dish['qty']?.toString() ?? "") != "N/A") {
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
                  if (!_checkAndConsumeSimulated(item, simulatedFridge)) {
                    isCovered = false;
                  }
                }
              }
              newMap["${day}_${mType}_$i"] = isCovered;
            }
          }
        }
      }
    }
    return newMap;
  }

  static List<List<int>> buildGroups(List<dynamic> dishes) {
    List<List<int>> groups = [];
    List<int> currentGroupIndices = [];
    for (int i = 0; i < dishes.length; i++) {
      final d = dishes[i];
      String qty = d['qty']?.toString() ?? "";
      bool isHeader = (qty == "N/A");
      if (isHeader) {
        if (currentGroupIndices.isNotEmpty) {
          groups.add(List.from(currentGroupIndices));
        }
        currentGroupIndices = [i];
      } else {
        if (currentGroupIndices.isNotEmpty) {
          currentGroupIndices.add(i);
        } else {
          groups.add([i]);
        }
      }
    }
    if (currentGroupIndices.isNotEmpty) {
      groups.add(List.from(currentGroupIndices));
    }
    return groups;
  }

  static bool _checkAndConsumeSimulated(
    Map<String, dynamic> item,
    Map<String, double> fridge,
  ) {
    String iName = item['name'].toString().trim().toLowerCase();
    String iRawQty = item['qty'].toString().toLowerCase();
    double iQty = parseQty(iRawQty);

    // Normalizzazione rapida per simulazione
    if (iRawQty.contains('kg') ||
        (iRawQty.contains('l') && !iRawQty.contains('ml'))) {
      iQty *= 1000;
    }
    if (iRawQty.contains('vasetto')) iQty = 125.0;

    String? foundKey;
    for (var key in fridge.keys) {
      if (key.contains(iName) || iName.contains(key)) {
        foundKey = key;
        break;
      }
    }
    if (foundKey != null && fridge[foundKey]! > 0) {
      if (fridge[foundKey]! >= iQty) {
        fridge[foundKey] = fridge[foundKey]! - iQty;
        return true;
      } else {
        fridge[foundKey] = 0;
        return false;
      }
    }
    return false;
  }

  static double normalizeToGrams(double qty, String unit) {
    final u = unit.trim().toLowerCase();
    if (u == 'kg' || u == 'l') return qty * 1000;
    if (u == 'g' || u == 'ml' || u == 'mg' || u == 'gr' || u == 'grammi') {
      return qty;
    }
    if (u.contains('vasetto')) return qty * 125;
    if (u.contains('cucchiain')) return qty * 5;
    if (u.contains('cucchiaio')) return qty * 15;
    return -1.0;
  }

  static double parseQty(String raw) {
    // Gestione "q.b." normalizzato dal server
    if (raw.toLowerCase().contains("q.b")) return 0.0;

    final regExp = RegExp(r'(\d+[.,]?\d*)');
    final match = regExp.firstMatch(raw);
    if (match != null) {
      return double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 1.0;
    }
    return 1.0;
  }

  // PARSER UNITÀ: Semplificato grazie alla normalizzazione Server-Side
  static String parseUnit(String raw, String name) {
    String lower = raw.toLowerCase().trim();

    // 1. Unità Standard (Normalizzate dal Server)
    if (lower.contains('kg')) return 'kg';
    if (lower.contains('mg')) return 'mg';
    if (lower.contains('ml')) return 'ml';
    if (lower.contains(' l ') || lower.endsWith(' l')) {
      return 'l'; // " l" o fine stringa per evitare 'ml'
    }

    // Regex per 'g' isolato o 'gr'
    if (RegExp(r'\b(g|gr)\b').hasMatch(lower)) return 'g';

    // Unità discrete (Il server ora manda sempre il singolare standard)
    if (lower.contains('vasetto')) return 'vasetto';
    if (lower.contains('cucchiaino')) return 'cucchiaino';
    if (lower.contains('cucchiaio')) return 'cucchiaio';
    if (lower.contains('tazza')) return 'tazza';
    if (lower.contains('bicchiere')) return 'bicchiere';
    if (lower.contains('fette')) return 'fette';

    // --- Retro-compatibilità (per diete vecchie in cache non normalizzate) ---
    if (lower.contains('vasetti')) return 'vasetto';
    if (lower.contains('cucchiai')) return 'cucchiaio'; // Plurale vecchio
    if (lower.contains('grammi')) return 'g';
    if (lower.contains('litri')) return 'l';
    // -----------------------------------------------------------------------

    if (lower.contains('pz')) return 'pz';

    // Fallback: se c'è un numero ma nessuna unità nota, è un pezzo (es "1 mela")
    return 'pz';
  }
}
