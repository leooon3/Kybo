import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // Ensure you have .env loaded if using backend URL
// If you don't have dotenv set up in web yet, hardcode the backend URL for now.

class AdminRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // 1. Fetch All Users
  Stream<List<Map<String, dynamic>>> getAllUsers() {
    return _db.collection('users').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }

  // 2. Toggle Ban/Active
  Future<void> toggleUserStatus(String uid, bool currentStatus) async {
    await _db.collection('users').doc(uid).update({
      'is_active': !currentStatus,
    });
  }

  // 3. Create User (God Mode)
  // Uses a secondary app instance to prevent logging out the Admin
  Future<void> createUser({
    required String email,
    required String password,
    required String role,
    String? parentId,
  }) async {
    FirebaseApp secondaryApp = await Firebase.initializeApp(
      name: 'SecondaryApp',
      options: Firebase.app().options,
    );

    try {
      UserCredential cred = await FirebaseAuth.instanceFor(
        app: secondaryApp,
      ).createUserWithEmailAndPassword(email: email, password: password);

      // Create Database Record
      await _db.collection('users').doc(cred.user!.uid).set({
        'uid': cred.user!.uid,
        'email': email,
        'role': role,
        'parent_id': parentId,
        'is_active': true,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Sign out the secondary user immediately so it doesn't interfere
      await FirebaseAuth.instanceFor(app: secondaryApp).signOut();
    } catch (e) {
      throw e; // Rethrow to UI
    }
  }

  // 4. Upload Diet (Inject PDF)
  Future<void> uploadDietForUser(String targetUid, PlatformFile file) async {
    // You need your FastAPI URL here.
    // If running locally on Windows/Web, use localhost.
    const String backendUrl = "http://127.0.0.1:8000";

    var request = http.MultipartRequest(
      'POST',
      Uri.parse(
        '$backendUrl/upload-diet/$targetUid',
      ), // You need to update backend to accept target_uid
    );

    // [IMPORTANT] Web requires using `bytes`, not `path`
    request.files.add(
      http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
    );

    var response = await request.send();
    if (response.statusCode != 200) {
      throw Exception("Upload Failed: ${response.reasonPhrase}");
    }
  }
}
