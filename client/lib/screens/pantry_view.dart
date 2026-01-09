import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/diet_provider.dart';
import '../constants.dart';

class PantryView extends StatefulWidget {
  const PantryView({super.key});

  @override
  State<PantryView> createState() => _PantryViewState();
}

class _PantryViewState extends State<PantryView> {
  void _showAddDialog(BuildContext context) {
    final nameController = TextEditingController();
    final qtyController = TextEditingController();
    String selectedUnit = 'pz';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text("Aggiungi alla Dispensa"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: "Nome Prodotto"),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyController,
                        decoration: const InputDecoration(
                          labelText: "Quantità",
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    DropdownButton<String>(
                      value: selectedUnit,
                      items: ['pz', 'g', 'ml', 'kg', 'L', 'cucchiai'].map((u) {
                        return DropdownMenuItem(value: u, child: Text(u));
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setStateDialog(() => selectedUnit = val);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Annulla"),
              ),
              FilledButton(
                onPressed: () {
                  if (nameController.text.isNotEmpty) {
                    // USA IL PROVIDER DIRETTAMENTE
                    Provider.of<DietProvider>(
                      context,
                      listen: false,
                    ).addPantryItem(
                      nameController.text,
                      double.tryParse(qtyController.text) ?? 1.0,
                      selectedUnit,
                    );
                    Navigator.pop(context);
                  }
                },
                child: const Text("Aggiungi"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DietProvider>(
      builder: (context, provider, child) {
        final pantryItems = provider.pantryItems;

        return Scaffold(
          backgroundColor: AppColors.scaffoldBackground,
          body: Column(
            children: [
              // Header Statistico (Opzionale)
              if (pantryItems.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${pantryItems.length} Prodotti",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      // Tasto svuota (Opzionale)
                      //IconButton(icon: Icon(Icons.delete_sweep),onPressed: () => provider.clearPantry(),),
                    ],
                  ),
                ),

              Expanded(
                child: pantryItems.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.kitchen,
                              size: 64,
                              color: Colors.grey[300],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              "La dispensa è vuota",
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: pantryItems.length,
                        itemBuilder: (context, index) {
                          final item = pantryItems[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary.withValues(
                                  alpha: 0.1,
                                ),
                                child: Text(
                                  item.name.isNotEmpty
                                      ? item.name[0].toUpperCase()
                                      : "?",
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                              title: Text(
                                item.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                "${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}",
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                ),
                                onPressed: () {
                                  provider.removePantryItem(index);
                                },
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            backgroundColor: AppColors.primary,
            onPressed: () => _showAddDialog(context),
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }
}
