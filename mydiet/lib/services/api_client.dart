import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/env.dart';

// [FIX] Custom Exceptions
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

  Future<dynamic> uploadFile(String endpoint, String filePath) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${Env.apiUrl}$endpoint'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', filePath));

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return json.decode(utf8.decode(response.bodyBytes));
      } else {
        // [FIX] Throw specific exception
        throw ApiException(
          'Server returned error: ${response.body}',
          response.statusCode,
        );
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      // [FIX] Wrap generic errors
      throw NetworkException('Network or parsing error: $e');
    }
  }
}
