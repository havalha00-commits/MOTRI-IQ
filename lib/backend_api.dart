import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class BackendApiException implements Exception {
  const BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendApi {
  BackendApi({
    required String baseUrl,
    String? Function()? accessToken,
    Future<String?> Function()? accessTokenAsync,
    String? Function()? backendAccessToken,
    Future<String?> Function()? backendAccessTokenAsync,
    bool backendOnly = false, // M1E-ISOLATION: when true, never use non-backend/Supabase token fallback.
    http.Client? client,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _accessToken = accessToken,
        _accessTokenAsync = accessTokenAsync,
        _backendAccessToken = backendAccessToken,
        _backendAccessTokenAsync = backendAccessTokenAsync,
        _backendOnly = backendOnly,
        _client = client ?? http.Client(),
        _ownsClient = client == null;

  final String _baseUrl;
  final String? Function()? _accessToken;
  final Future<String?> Function()? _accessTokenAsync;
  final String? Function()? _backendAccessToken;
  final Future<String?> Function()? _backendAccessTokenAsync;
  final bool _backendOnly;
  final http.Client _client;
  final bool _ownsClient;

  Future<String?> _resolveToken({bool backendOnly = false}) async {
    final mustUseBackend = backendOnly || _backendOnly;
    if (mustUseBackend) {
      if (_backendAccessTokenAsync != null) {
        final t = await _backendAccessTokenAsync();
        if (t != null && t.isNotEmpty) return t;
      }
      if (_backendAccessToken != null) {
        final t = _backendAccessToken();
        if (t != null && t.isNotEmpty) return t;
      }
      return null;
    }
    // Existing behavior outside isolation: prefer backend token, then general/Supabase fallback.
    if (_backendAccessTokenAsync != null) {
      final t = await _backendAccessTokenAsync();
      if (t != null && t.isNotEmpty) return t;
    }
    if (_backendAccessToken != null) {
      final t = _backendAccessToken();
      if (t != null && t.isNotEmpty) return t;
    }
    if (_accessTokenAsync != null) {
      final t = await _accessTokenAsync();
      if (t != null && t.isNotEmpty) return t;
    }
    if (_accessToken != null) {
      final t = _accessToken();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }

  Future<dynamic> get(String path,
          {Map<String, String>? query,
          bool backendOnly = false,
          bool anonymous = false}) =>
      _send('GET', path,
          query: query, backendOnly: backendOnly, anonymous: anonymous);

  Future<dynamic> post(String path, {Map<String, dynamic>? body, bool backendOnly = false}) =>
      _send('POST', path, body: body, backendOnly: backendOnly);

  Future<dynamic> put(String path, {Map<String, dynamic>? body, bool backendOnly = false}) =>
      _send('PUT', path, body: body, backendOnly: backendOnly);

  Future<dynamic> patch(String path, {Map<String, dynamic>? body, bool backendOnly = false}) =>
      _send('PATCH', path, body: body, backendOnly: backendOnly);

  Future<dynamic> delete(String path, {bool backendOnly = false}) => _send('DELETE', path, backendOnly: backendOnly);

  Future<dynamic> putBytes(
    String path, {
    required Uint8List body,
    required String contentType,
    Map<String, String>? query,
    bool backendOnly = false,
  }) =>
      _sendBytes('PUT', path, body: body, contentType: contentType, query: query, backendOnly: backendOnly);

  Future<dynamic> postBytes(
    String path, {
    required Uint8List body,
    required String contentType,
    Map<String, String>? query,
    bool backendOnly = false,
  }) =>
      _sendBytes('POST', path,
          body: body, contentType: contentType, query: query, backendOnly: backendOnly);

  Future<dynamic> _sendBytes(
    String method,
    String path, {
    required Uint8List body,
    required String contentType,
    Map<String, String>? query,
    bool backendOnly = false,
  }) async {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$_baseUrl/api/$normalizedPath')
        .replace(queryParameters: query);
    final effectiveBackendOnly = backendOnly || _backendOnly;
    final token = await _resolveToken(backendOnly: backendOnly);
    if (effectiveBackendOnly && (token == null || token.isEmpty)) {
      throw const BackendApiException('Backend authentication required');
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': contentType,
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    try {
      final request = http.Request(method, uri)
        ..headers.addAll(headers)
        ..bodyBytes = body;
      final response =
          await _client.send(request).timeout(const Duration(seconds: 30));
      final streamed = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 30));
      dynamic decoded;
      if (streamed.isNotEmpty) {
        try {
          decoded = jsonDecode(streamed);
        } on FormatException {
          throw const BackendApiException('استجابة الخادم غير صالحة');
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['error']?.toString() ??
                decoded['message']?.toString() ??
                'فشل الاتصال بالخادم'
            : 'فشل الاتصال بالخادم';
        throw BackendApiException(message, statusCode: response.statusCode);
      }
      return decoded;
    } on BackendApiException {
      rethrow;
    } on TimeoutException {
      throw const BackendApiException('انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      throw const BackendApiException('تعذر الاتصال بخادم التطبيق');
    }
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool backendOnly = false,
    bool anonymous = false,
  }) async {
    final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse('$_baseUrl/api/$normalizedPath')
        .replace(queryParameters: query);
    final effectiveBackendOnly = !anonymous && (backendOnly || _backendOnly);
    final token =
        anonymous ? null : await _resolveToken(backendOnly: backendOnly);
    if (effectiveBackendOnly && (token == null || token.isEmpty)) {
      throw const BackendApiException('Backend authentication required');
    }
    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    try {
      final response = await _client
          .send(http.Request(method, uri)
            ..headers.addAll(headers)
            ..body = body == null ? '' : jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      final streamed = await response.stream
          .bytesToString()
          .timeout(const Duration(seconds: 30));
      dynamic decoded;
      if (streamed.isNotEmpty) {
        try {
          decoded = jsonDecode(streamed);
        } on FormatException {
          throw const BackendApiException('استجابة الخادم غير صالحة');
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map
            ? decoded['error']?.toString() ??
                decoded['message']?.toString() ??
                'فشل الاتصال بالخادم'
            : 'فشل الاتصال بالخادم';
        throw BackendApiException(message, statusCode: response.statusCode);
      }
      return decoded;
    } on BackendApiException {
      rethrow;
    } on TimeoutException {
      throw const BackendApiException('انتهت مهلة الاتصال بالخادم');
    } catch (_) {
      throw const BackendApiException('تعذر الاتصال بخادم التطبيق');
    }
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}
