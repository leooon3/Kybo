class ActiveSwap {
  final String name; // Nome descrittivo (es. "Pasta e Fagioli")
  final String qty;
  final String unit;
  final List<dynamic>? swappedIngredients; // La lista dei nuovi ingredienti

  ActiveSwap({
    required this.name,
    required this.qty,
    this.unit = "",
    this.swappedIngredients,
  });

  // --- SERIALIZZAZIONE (Verso Firestore) ---
  Map<String, dynamic> toJson() => {
        'name': name,
        'qty': qty,
        'unit': unit,
        'swappedIngredients': swappedIngredients,
      };

  // Alias per chiarezza con Firestore
  Map<String, dynamic> toMap() => toJson();

  // --- DESERIALIZZAZIONE (Da Firestore) ---
  factory ActiveSwap.fromJson(Map<String, dynamic> json) {
    return ActiveSwap(
      name: json['name'] ?? '',
      qty: json['qty']?.toString() ?? '',
      unit: json['unit'] ?? '',
      // Gestione sicura della lista ingredienti
      swappedIngredients: json['swappedIngredients'] != null
          ? List<dynamic>.from(json['swappedIngredients'])
          : null,
    );
  }

  // Alias per chiarezza con Firestore
  factory ActiveSwap.fromMap(Map<String, dynamic> map) =>
      ActiveSwap.fromJson(map);
}
