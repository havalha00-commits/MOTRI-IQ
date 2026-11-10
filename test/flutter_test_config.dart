import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _TestStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? iOptions2,
    AppleOptions? webOptions2,
    WindowsOptions? wOptions2,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? iOptions2,
    AppleOptions? webOptions2,
    WindowsOptions? wOptions2,
  }) async =>
      _values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
    AppleOptions? iOptions2,
    AppleOptions? webOptions2,
    WindowsOptions? wOptions2,
  }) async {
    _values.remove(key);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  backendAuthSession = BackendAuthSession(
    baseUrl: 'https://test.invalid',
    storage: _TestStorage(),
    client: MockClient((_) async => http.Response(jsonEncode({}), 404)),
  );
  await testMain();
}
