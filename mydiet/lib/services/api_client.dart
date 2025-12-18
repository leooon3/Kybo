import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import '../core/env.dart';

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);
  @override
  String toString() => 'ApiException: $message (Code: $statusCode)';
}

class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  @override
  String toString() => 'NetworkException: $message';
}

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal();

  Future<dynamic> uploadFile(
    String endpoint,
    String filePath, {
    Map<String, String>? fields,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.apiUrl}$endpoint'),
      );

      // --- SECURITY: Aggiungi Token Firebase ---
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // [FIX] Use cached token (false) instead of forcing refresh on every call.
        // The SDK handles expiration automatically.
        final token = await user.getIdToken(false);
        request.headers['Authorization'] = 'Bearer $token';
      }
      // ----------------------------------------

      // Add the file
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // Add extra fields if provided
      if (fields != null) {
        request.fields.addAll(fields);
      }

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        throw ApiException(
          'Server returned error: ${response.body}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network or parsing error: $e');
    }
  }
}
