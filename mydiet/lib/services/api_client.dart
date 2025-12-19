import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:retry/retry.dart';
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
    // Retry only on network errors, not on timeouts (since we removed the timeout)
    final r = RetryOptions(
      maxAttempts: 3,
      delayFactor: const Duration(seconds: 1),
    );

    try {
      return await r.retry(
        () async {
          return await _performUpload(endpoint, filePath, fields);
        },
        retryIf: (e) =>
            e is NetworkException || (e is ApiException && e.statusCode >= 500),
      );
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Operation failed: $e');
    }
  }

  Future<dynamic> _performUpload(
    String endpoint,
    String filePath,
    Map<String, String>? fields,
  ) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.apiUrl}$endpoint'),
      );

      // Auth Token
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken(false);
        request.headers['Authorization'] = 'Bearer $token';
      }

      // Add File
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      // Add Fields
      if (fields != null) {
        request.fields.addAll(fields);
      }

      // [CHANGE] No timeout. Waits forever for the server.
      var streamedResponse = await request.send();

      var response = await http.Response.fromStream(streamedResponse);

      // Handle Response
      if (response.statusCode >= 200 && response.statusCode < 300) {
        if (response.body.isEmpty) return {};
        try {
          return json.decode(utf8.decode(response.bodyBytes));
        } catch (e) {
          throw ApiException(
            "Invalid JSON response from server",
            response.statusCode,
          );
        }
      } else {
        // Parse Error
        String errorMsg = response.body;
        try {
          final errorJson = json.decode(utf8.decode(response.bodyBytes));
          if (errorJson is Map && errorJson.containsKey('detail')) {
            final detail = errorJson['detail'];
            errorMsg = detail is String ? detail : detail.toString();
          }
        } catch (_) {
          // Truncate non-JSON HTML errors
          if (errorMsg.length > 200) {
            errorMsg = "${errorMsg.substring(0, 200)}...";
          }
        }
        throw ApiException(errorMsg, response.statusCode);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw NetworkException('Network error: $e');
    }
  }
}
