import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class AuthSessionUser {
  const AuthSessionUser({
    required this.id,
    required this.email,
    required this.isAdmin,
    this.username,
    this.fullName,
    this.phone,
    this.avatarUrl,
  });

  final String id;
  final String email;
  final bool isAdmin;
  final String? username;
  final String? fullName;
  final String? phone;
  final String? avatarUrl;

  static String? _clean(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory AuthSessionUser.fromJson(
    Map<String, dynamic> json, {
    AuthSessionUser? previous,
  }) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const AuthSessionException('بيانات المستخدم غير صالحة');
    }
    final email = _clean(json['email']) ?? previous?.email ?? '';
    if (email.isEmpty) {
      throw const AuthSessionException('بيانات المستخدم غير صالحة');
    }
    final prevSame = previous != null && previous.id == id ? previous : null;
    return AuthSessionUser(
      id: id,
      email: email,
      isAdmin: json['is_admin'] == true || json['isAdmin'] == true,
      username: _clean(json['username']) ?? prevSame?.username,
      fullName: _clean(json['full_name'] ?? json['fullName'] ?? json['display_name']) ??
          prevSame?.fullName,
      phone: _clean(json['phone']) ?? prevSame?.phone,
      avatarUrl: _clean(json['avatar_url'] ?? json['avatarUrl']) ?? prevSame?.avatarUrl,
    );
  }

  AuthSessionUser mergeProfile(Map<String, dynamic> json) {
    if (json['id'] != null && json['id'].toString() != id) return this;
    return AuthSessionUser(
      id: id,
      email: _clean(json['email']) ?? email,
      isAdmin: json.containsKey('is_admin') || json.containsKey('isAdmin')
          ? (json['is_admin'] == true || json['isAdmin'] == true)
          : isAdmin,
      username: _clean(json['username']) ?? username,
      fullName: _clean(json['full_name'] ?? json['fullName'] ?? json['display_name']) ?? fullName,
      phone: _clean(json['phone']) ?? phone,
      avatarUrl: _clean(json['avatar_url'] ?? json['avatarUrl']) ?? avatarUrl,
    );
  }

  AuthSessionUser copyWith({
    String? email,
    bool? isAdmin,
    String? username,
    String? fullName,
    String? phone,
    String? avatarUrl,
    bool clearUsername = false,
    bool clearFullName = false,
    bool clearPhone = false,
    bool clearAvatarUrl = false,
  }) {
    return AuthSessionUser(
      id: id,
      email: email ?? this.email,
      isAdmin: isAdmin ?? this.isAdmin,
      username: clearUsername ? null : (username ?? this.username),
      fullName: clearFullName ? null : (fullName ?? this.fullName),
      phone: clearPhone ? null : (phone ?? this.phone),
      avatarUrl: clearAvatarUrl ? null : (avatarUrl ?? this.avatarUrl),
    );
  }
}

/// Backward-compatible alias; prefer [AuthSessionUser] for the independent auth model.
typedef BackendUser = AuthSessionUser;

class AuthSessionException implements Exception {
  const AuthSessionException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class BackendAuthSession extends ChangeNotifier {
  BackendAuthSession({
    required String baseUrl,
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _storage = storage ?? const FlutterSecureStorage();

  static const String _refreshKey = 'motri.backend.refresh_token';

  final String _baseUrl;
  final http.Client _client;
  final bool _ownsClient;
  final FlutterSecureStorage _storage;

  AuthSessionUser? _user;
  String? _accessToken;
  DateTime? _accessExpiresAt;
  Future<bool>? _refreshInProgress;
  bool _disposed = false;

  AuthSessionUser? get user => _user;
  String? get accessToken => _accessToken;
  bool get isAuthenticated => _user != null && _accessToken != null;

  Uri _endpoint(String path) => Uri.parse('$_baseUrl/api/auth/$path');

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client
          .post(
            _endpoint(path),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 20));

      Map<String, dynamic>? data;

      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      } on FormatException {
        // نتعامل مع حالة الاستجابة أدناه.
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AuthSessionException(
          data?['error']?.toString() ?? 'فشلت عملية المصادقة',
          statusCode: response.statusCode,
        );
      }

      if (data == null) {
        throw const AuthSessionException('استجابة المصادقة غير صالحة');
      }

      return data;
    } on AuthSessionException {
      rethrow;
    } on TimeoutException {
      throw const AuthSessionException('انتهت مهلة الاتصال بالخادم');
    } on FormatException {
      throw const AuthSessionException('استجابة الخادم غير مفهومة');
    } catch (_) {
      throw const AuthSessionException('تعذر الاتصال بخادم المصادقة');
    }
  }

  void _applyTokens(Map<String, dynamic> data) {
    final access = data['access_token'];
    final refresh = data['refresh_token'];
    final userData = data['user'];

    if (data['authenticated'] != true ||
        access is! String ||
        access.isEmpty ||
        refresh is! String ||
        refresh.isEmpty ||
        userData is! Map) {
      throw const AuthSessionException(
        'بيانات الجلسة المستلمة غير مكتملة',
      );
    }

    final userMap = Map<String, dynamic>.from(userData);
    final expiresIn = data['expires_in'];
    final seconds = expiresIn is num ? expiresIn.toInt() : 900;

    _accessToken = access;
    _accessExpiresAt = DateTime.now().add(
      Duration(seconds: seconds > 0 ? seconds : 900),
    );
    _user = AuthSessionUser.fromJson(userMap, previous: _user);
  }

  Future<void> loadProfile() async {
    final uid = _user?.id;
    final token = await validAccessToken();
    if (token == null || token.isEmpty || uid == null) return;
    try {
      final uri = Uri.parse('$_baseUrl/api/profile/me');
      final response = await _client
          .get(uri, headers: {
            'Accept': 'application/json',
            'Authorization': 'Bearer $token',
          })
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) return;
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      if (data is! Map) return;
      final current = _user;
      if (current == null || current.id != uid) return; // logout/account switch
      final profile = Map<String, dynamic>.from(data);
      final pid = profile['id']?.toString();
      if (pid != null && pid.isNotEmpty && pid != current.id) return;
      _user = current.mergeProfile(profile);
      _notify();
    } catch (_) {
      // Best-effort enrichment; session remains valid.
    }
  }

  void applyProfile(Map<String, dynamic> profileData) {
    if (_user == null) return;
    _user = _user!.mergeProfile(profileData);
    _notify();
  }

  void setUsername(String username) {
    if (_user == null) return;
    final clean = username.trim().toLowerCase();
    if (clean.isEmpty) return;
    _user = _user!.copyWith(username: clean);
    _notify();
  }

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    String? fullName,
    String? username,
  }) async {
    final data = await _post('register', {
      'email': email.trim(),
      'password': password,
      if (fullName != null && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
      if (username != null && username.trim().isNotEmpty)
        'username': username.trim().toLowerCase(),
    });
    final requires = data['requires_email_confirmation'] == true;
    if (requires) return data;
    final refresh = data['refresh_token'];
    if (refresh is! String || refresh.isEmpty) {
      throw const AuthSessionException('رمز الجلسة المستلم غير صالح');
    }
    try {
      await _storage.write(key: _refreshKey, value: refresh);
    } catch (_) {
      try {
        await _post('logout', {'refresh_token': refresh});
      } catch (_) {}
      _clearMemory();
      throw const AuthSessionException('تعذر حفظ الجلسة على الجهاز');
    }
    try {
      _applyTokens(data);
    } catch (_) {
      try {
        await _storage.delete(key: _refreshKey);
      } catch (_) {}
      _clearMemory();
      rethrow;
    }
    _notify();
    unawaited(loadProfile().catchError((_) {}));
    return data;
  }

  Future<void> login({
    String? email,
    String? identifier,
    required String password,
  }) async {
    final id = (identifier ?? email ?? '').trim();
    final data = await _post('login', {
      'identifier': id,
      if (id.contains('@')) 'email': id else 'username': id.toLowerCase(),
      'password': password,
    });

    final refresh = data['refresh_token'];
    if (refresh is! String || refresh.isEmpty) {
      throw const AuthSessionException('رمز الجلسة المستلم غير صالح');
    }

    try {
      await _storage.write(key: _refreshKey, value: refresh);
    } catch (_) {
      try {
        await _post('logout', {'refresh_token': refresh});
      } catch (_) {}
      _clearMemory();
      throw const AuthSessionException('تعذر حفظ الجلسة على الجهاز');
    }

    try {
      _applyTokens(data);
    } catch (_) {
      try {
        await _storage.delete(key: _refreshKey);
      } catch (_) {}
      _clearMemory();
      rethrow;
    }

    _notify();
    unawaited(loadProfile().catchError((_) {}));
  }

  Future<bool> restoreSession() async {
    String? token;

    try {
      token = await _storage.read(key: _refreshKey);
    } catch (_) {
      throw const AuthSessionException('تعذر قراءة الجلسة المحفوظة');
    }

    if (token == null || token.isEmpty) {
      _clearMemory();
      _notify();
      return false;
    }

    return refresh();
  }

  Future<bool> refresh() {
    final running = _refreshInProgress;
    if (running != null) return running;

    final future = _refreshInternal();
    _refreshInProgress = future;

    return future.whenComplete(() {
      if (identical(_refreshInProgress, future)) {
        _refreshInProgress = null;
      }
    });
  }

  Future<bool> _refreshInternal() async {
    String? token;

    try {
      token = await _storage.read(key: _refreshKey);
    } catch (_) {
      throw const AuthSessionException('تعذر قراءة الجلسة المحفوظة');
    }

    if (token == null || token.isEmpty) {
      _clearMemory();
      _notify();
      return false;
    }

    try {
      final data = await _post('refresh', {'refresh_token': token});
      final newRefresh = data['refresh_token'];

      if (newRefresh is! String || newRefresh.isEmpty) {
        throw const AuthSessionException('رمز التجديد المستلم غير صالح');
      }

      try {
        // نحفظ الرمز الجديد قبل اعتماد الجلسة في الذاكرة.
        await _storage.write(key: _refreshKey, value: newRefresh);
      } catch (_) {
        _clearMemory();
        try {
          await _storage.delete(key: _refreshKey);
        } catch (_) {}
        throw const AuthSessionException(
          'تعذر حفظ الجلسة الجديدة على الجهاز؛ سجّل الدخول مجدداً',
        );
      }

      _applyTokens(data);
      _notify();
      unawaited(loadProfile().catchError((_) {}));
      return true;
    } on AuthSessionException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        try {
          await _storage.delete(key: _refreshKey);
        } catch (_) {}
        _clearMemory();
        _notify();
        return false;
      }

      // أخطاء الإنترنت والخادم لا تحذف الرمز المحفوظ.
      rethrow;
    }
  }

  Future<String?> validAccessToken() async {
    final expiry = _accessExpiresAt;

    if (_accessToken == null ||
        expiry == null ||
        DateTime.now().isAfter(
          expiry.subtract(const Duration(seconds: 60)),
        )) {
      final restored = await refresh();
      if (!restored) return null;
    }

    return _accessToken;
  }

  Future<void> logout() async {
    try {
      final token = await _storage.read(key: _refreshKey);

      if (token != null && token.isNotEmpty) {
        await _post('logout', {'refresh_token': token});
      }
    } finally {
      try {
        await _storage.delete(key: _refreshKey);
      } finally {
        _clearMemory();
        _notify();
      }
    }
  }

  void _clearMemory() {
    _user = null;
    _accessToken = null;
    _accessExpiresAt = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
