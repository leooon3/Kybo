import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:csv/csv.dart'; // Per generare il CSV
import 'package:universal_html/html.dart' as html; // Per il download web
import 'dart:convert'; // Per utf8

class AuditLogView extends StatelessWidget {
  const AuditLogView({super.key});

  /// Funzione per esportare i dati in CSV
  Future<void> _exportCsv(List<QueryDocumentSnapshot> docs) async {
    List<List<dynamic>> rows = [];

    // 1. Intestazioni
    rows.add([
      "Data e Ora",
      "Admin Richiedente (ID)",
      "Azione",
      "Utente Target (ID)",
      "Motivazione Legale",
      "User Agent",
    ]);

    // 2. Dati
    for (var doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final timestamp = data['timestamp'] as Timestamp?;
      final dateStr = timestamp != null
          ? DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp.toDate())
          : 'N/A';

      rows.add([
        dateStr,
        data['requester_id'] ?? 'N/A',
        data['action'] ?? 'N/A',
        data['target_uid'] ?? 'N/A',
        data['reason'] ?? 'N/A',
        data['user_agent'] ?? 'N/A',
      ]);
    }

    // 3. Conversione in stringa CSV
    String csvData = const ListToCsvConverter().convert(rows);

    // 4. Download del file (Logica Web)
    final bytes = utf8.encode(csvData);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);

    // FIX: Rimossa assegnazione variabile 'anchor' inutilizzata
    html.AnchorElement(href: url)
      ..setAttribute(
        "download",
        "audit_logs_export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv",
      )
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Registro Accessi (Audit Log)"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // TASTO EXPORT CSV AGGIUNTO
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('access_logs')
                .orderBy('timestamp', descending: true)
                .limit(500) // Limite di sicurezza per l'export rapido
                .snapshots(),
            builder: (context, snapshot) {
              // Disabilita tasto se non ci sono dati pronti
              final bool hasData =
                  snapshot.hasData && snapshot.data!.docs.isNotEmpty;

              return IconButton(
                icon: const Icon(Icons.download),
                tooltip: "Scarica CSV (Legale)",
                onPressed: hasData
                    ? () => _exportCsv(snapshot.data!.docs)
                    : null,
              );
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('access_logs')
            .orderBy('timestamp', descending: true)
            .limit(100) // A schermo mostriamo solo gli ultimi 100 per velocità
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text("Errore caricamento log: ${snapshot.error}"),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final logs = snapshot.data!.docs;

          if (logs.isEmpty) {
            return const Center(
              child: Text("Nessun log di accesso registrato nel sistema."),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
                columns: const [
                  DataColumn(
                    label: Text(
                      "Data/Ora",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Admin",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Azione",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Target UID",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      "Motivazione",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: logs.map((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final timestamp = data['timestamp'] as Timestamp?;
                  final dateStr = timestamp != null
                      ? DateFormat(
                          'dd/MM/yyyy HH:mm:ss',
                        ).format(timestamp.toDate())
                      : '-';

                  return DataRow(
                    cells: [
                      DataCell(Text(dateStr)),
                      DataCell(
                        Text(
                          data['requester_id'] ?? 'Unknown',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            data['action'] ?? '-',
                            style: const TextStyle(
                              color: Colors.deepOrange,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          data['target_uid'] ?? '-',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DataCell(Text(data['reason'] ?? '-')),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }
}
