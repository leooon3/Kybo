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

  // Per salvare in memoria (JSON)
  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'unit': unit,
    'swappedIngredients': swappedIngredients,
  };

  // Per leggere dalla memoria
  factory ActiveSwap.fromJson(Map<String, dynamic> json) => ActiveSwap(
    name: json['name'] ?? '',
    qty: json['qty'] ?? '',
    unit: json['unit'] ?? '',
    swappedIngredients: json['swappedIngredients'],
  );
}
