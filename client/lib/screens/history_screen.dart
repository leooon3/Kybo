import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../providers/diet_provider.dart';
import '../core/error_handler.dart'; // [IMPORTANTE]

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final firestore = FirestoreService();

    return Scaffold(
      appBar: AppBar(title: const Text("Cronologia Diete")),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: firestore.getDietHistory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // [UX] Errore tradotto
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 50,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      ErrorMapper.toUserMessage(snapshot.error!),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 50, color: Colors.grey),
                  SizedBox(height: 10),
                  Text("Nessuna dieta salvata nel cloud."),
                ],
              ),
            );
          }

          final diets = snapshot.data!;
          return ListView.builder(
            itemCount: diets.length,
            itemBuilder: (context, index) {
              final diet = diets[index];
              DateTime date = DateTime.now();
              if (diet['uploadedAt'] != null) {
                date = (diet['uploadedAt'] as dynamic).toDate();
              }
              final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(date);

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  leading: const Icon(Icons.cloud_done, color: Colors.blue),
                  title: Text("Dieta del $dateStr"),
                  subtitle: const Text("Tocca per ripristinare"),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      try {
                        await firestore.deleteDiet(diet['id']);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(ErrorMapper.toUserMessage(e)),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text("Ripristina Dieta"),
                        content: const Text(
                          "Vuoi sostituire la dieta attuale con questa versione salvata?",
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c),
                            child: const Text("Annulla"),
                          ),
                          FilledButton(
                            onPressed: () {
                              context.read<DietProvider>().loadHistoricalDiet(
                                diet,
                              );
                              Navigator.pop(c);
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    "Dieta ripristinata con successo!",
                                  ),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            child: const Text("Ripristina"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
