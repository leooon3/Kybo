import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

class AdminRepository {
  final String _baseUrl = "https://mydiet-74rg.onrender.com";

  Future<String?> _getToken() async {
    return await FirebaseAuth.instance.currentUser?.getIdToken();
  }

  // --- 1. GESTIONE UTENTI ---

  Future<void> createUser({
    required String email,
    required String password,
    required String role,
    required String firstName,
    required String lastName,
  }) async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/create-user'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'email': email,
        'password': password,
        'role': role,
        'first_name': firstName,
        'last_name': lastName,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create user: ${response.body}');
    }
  }

  Future<void> deleteUser(String uid) async {
    final token = await _getToken();
    final response = await http.delete(
      Uri.parse('$_baseUrl/admin/delete-user/$uid'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to delete user: ${response.body}');
    }
  }

  // [RIPRISTINATO] Sync Users (Cruciale per allineare Auth e Firestore)
  Future<String> syncUsers() async {
    final token = await _getToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/admin/sync-users'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['message'] ?? "Sync completato.";
    } else {
      throw Exception("Sync fallito: ${response.body}");
    }
  }

  // --- 2. UPLOAD FILE ---

  Future<void> uploadDietForUser(String targetUid, PlatformFile file) async {
    final token = await _getToken();

    if (file.bytes == null) throw Exception("File corrotto o vuoto");

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/upload-diet/$targetUid'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('application', 'pdf'),
      ),
    );

    final response = await request.send();

    if (response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Upload failed: $respStr');
    }
  }

  Future<void> uploadParserConfig(String targetUid, PlatformFile file) async {
    final token = await _getToken();

    if (file.bytes == null) throw Exception("File vuoto");

    var request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/admin/upload-parser/$targetUid'),
    );
    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
        contentType: MediaType('text', 'plain'),
      ),
    );

    final response = await request.send();
    if (response.statusCode != 200) {
      final respStr = await response.stream.bytesToString();
      throw Exception('Parser upload failed: $respStr');
    }
  }

  // --- 3. CONFIGURAZIONE ---

  Future<bool> getMaintenanceStatus() async {
    final token = await _getToken();
    final response = await http.get(
      Uri.parse('$_baseUrl/admin/config/maintenance'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['enabled'] ?? false;
    }
    return false;
  }

  Future<void> setMaintenanceStatus(bool enabled) async {
    final token = await _getToken();
    await http.post(
      Uri.parse('$_baseUrl/admin/config/maintenance'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'enabled': enabled}),
    );
  }
}
