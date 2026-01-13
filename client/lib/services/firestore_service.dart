import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // [MODIFICATO] Ora accetta anche 'swaps' (le modifiche dell'utente)
  Future<String> saveDietToHistory(
    Map<String, dynamic> plan,
    Map<String, dynamic> subs,
    Map<String, dynamic> swaps, // <--- NUOVO PARAMETRO
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) throw Exception("Utente non loggato");

      final docRef =
          await _db.collection('users').doc(user.uid).collection('diets').add({
        'uploadedAt': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
        'plan': plan,
        'substitutions': subs,
        'activeSwaps': swaps, // <--- SALVIAMO LE TUE MODIFICHE
      });

      debugPrint("🆕 Nuova dieta creata con ID: ${docRef.id}");
      return docRef.id;
    } catch (e) {
      debugPrint("⚠️ Errore creazione storico: $e");
      rethrow;
    }
  }

  // [MODIFICATO] Aggiorna anche gli swaps
  Future<void> updateDietHistory(
    String docId,
    Map<String, dynamic> plan,
    Map<String, dynamic> subs,
    Map<String, dynamic> swaps, // <--- NUOVO PARAMETRO
  ) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('diets')
          .doc(docId)
          .update({
        'lastUpdated': FieldValue.serverTimestamp(),
        'plan': plan,
        'substitutions': subs,
        'activeSwaps': swaps, // <--- AGGIORNIAMO LE TUE MODIFICHE
      });

      debugPrint("🔄 Dieta $docId aggiornata su Cloud (con modifiche).");
    } catch (e) {
      debugPrint("⚠️ Errore aggiornamento storico: $e");
      rethrow;
    }
  }

  Stream<Map<String, dynamic>?> getDietStream() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(null);

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('diets')
        .doc('current')
        .snapshots()
        .map((snapshot) => snapshot.exists ? snapshot.data() : null);
  }

  Stream<List<Map<String, dynamic>>> getDietHistory() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value([]);

    return _db
        .collection('users')
        .doc(user.uid)
        .collection('diets')
        .orderBy('uploadedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => {'id': doc.id, ...doc.data()})
              .toList(),
        );
  }

  Future<void> deleteDiet(String dietId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;

      await _db
          .collection('users')
          .doc(user.uid)
          .collection('diets')
          .doc(dietId)
          .delete();
    } catch (e) {
      debugPrint("❌ Errore eliminazione dieta: $e");
      rethrow;
    }
  }
}
