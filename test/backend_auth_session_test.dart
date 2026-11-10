import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';

class _MemStorage extends FlutterSecureStorage {
  _MemStorage();
  final Map<String, String> m = {};
  @override
  Future<void> write({required String key, required String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions}) async {
    if (value == null) { m.remove(key); } else { m[key] = value; }
  }
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions}) async => m[key];
  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions}) async { m.remove(key); }
}

String js(Object o) => jsonEncode(o);

void main() {
  test('parses missing profile fields safely', () async {
    final s = BackendAuthSession(baseUrl: 'https://x', storage: _MemStorage(), client: MockClient((_) async => http.Response('{"authenticated":true,"access_token":"a","refresh_token":"r","expires_in":900,"user":{"id":"u-1","email":"a@b.c","is_admin":false}}', 200)));
    await s.login(email: 'a@b.c', password: 'p');
    expect(s.user?.id, 'u-1');
    expect(s.user?.username, isNull);
    s.dispose();
  });

  test('login preserves UUID and applies profile fields', () async {
    final s = BackendAuthSession(baseUrl: 'https://x', storage: _MemStorage(), client: MockClient((_) async => http.Response(js({'authenticated': true, 'access_token': 'a', 'refresh_token': 'r', 'expires_in': 900, 'user': {'id':'u-1','email':'a@b.c','is_admin':true,'username':'name','full_name':'Full','phone':'077','avatar_url':'https://p'}}), 200)));
    await s.login(email: 'a@b.c', password: 'p');
    expect(s.user?.id, 'u-1');
    expect(s.user?.isAdmin, true);
    expect(s.user?.username, 'name');
    s.dispose();
  });

  test('refresh keeps UUID and merges profile', () async {
    final storage = _MemStorage();
    final s = BackendAuthSession(baseUrl: 'https://x', storage: storage, client: MockClient((req) async {
      if (req.url.path.endsWith('/login')) return http.Response(js({'authenticated':true,'access_token':'a1','refresh_token':'r1','expires_in':1,'user':{'id':'u-1','email':'a@b.c','is_admin':false,'full_name':'Old'}}), 200);
      return http.Response(js({'authenticated':true,'access_token':'a2','refresh_token':'r2','expires_in':900,'user':{'id':'u-1','email':'a@b.c','is_admin':false,'full_name':'New','username':'u'}}), 200);
    }));
    await s.login(email:'a@b.c', password:'p');
    await storage.write(key: 'motri.backend.refresh_token', value: 'r1');
    final ok = await s.refresh();
    expect(ok, true);
    expect(s.user?.id, 'u-1');
    expect(s.user?.fullName, 'New');
    s.dispose();
  });

  test('applyProfile updates without changing UUID; logout clears', () async {
    final s = BackendAuthSession(baseUrl: 'https://x', storage: _MemStorage(), client: MockClient((req) async {
      if (req.url.path.endsWith('/logout')) return http.Response('{"logged_out":true}', 200);
      return http.Response(js({'authenticated':true,'access_token':'a','refresh_token':'r','expires_in':900,'user':{'id':'u-1','email':'a@b.c','is_admin':false}}), 200);
    }));
    await s.login(email:'a@b.c', password:'p');
    s.applyProfile({'id':'u-1','full_name':'Name'});
    expect(s.user?.id, 'u-1');
    s.applyProfile({'id':'other','full_name':'Bad'});
    expect(s.user?.fullName, 'Name');
    await s.logout();
    expect(s.user, isNull);
    expect(s.isAuthenticated, false);
    s.dispose();
  });

  test('restoreSession false when no token', () async {
    final s = BackendAuthSession(baseUrl:'https://x', storage:_MemStorage(), client: MockClient((_) async => http.Response('{}', 500)));
    expect(await s.restoreSession(), false);
    expect(s.user, isNull);
    s.dispose();
  });

  test('setUsername preserves UUID', () async {
    final s = BackendAuthSession(baseUrl:'https://x', storage:_MemStorage(), client: MockClient((_) async => http.Response(js({'authenticated':true,'access_token':'a','refresh_token':'r','expires_in':900,'user':{'id':'u-1','email':'a@b.c','is_admin':false}}), 200)));
    await s.login(email:'a@b.c', password:'p');
    s.setUsername('New_User');
    expect(s.user?.id, 'u-1');
    expect(s.user?.username, 'new_user');
    s.dispose();
  });

  test('G8 restoreSession restores valid session from stored refresh token', () async {
    final storage = _MemStorage();
    await storage.write(key: 'motri.backend.refresh_token', value: 'stored-r');
    final s = BackendAuthSession(baseUrl:'https://x', storage: storage, client: MockClient((req) async {
      if (req.url.path.endsWith('/refresh')) {
        return http.Response(js({'authenticated':true,'access_token':'a2','refresh_token':'r2','expires_in':900,'user':{'id':'u-1','email':'a@b.c','is_admin':false,'username':'name'}}), 200);
      }
      return http.Response('{}', 404);
    }));
    final ok = await s.restoreSession();
    expect(ok, true);
    expect(s.isAuthenticated, true);
    expect(s.user?.id, 'u-1');
    expect(s.user?.username, 'name');
    s.dispose();
  });

  test('G8 restoreSession fails safely on expired invalid refresh and clears session', () async {
    final storage = _MemStorage();
    await storage.write(key: 'motri.backend.refresh_token', value: 'bad');
    final s = BackendAuthSession(baseUrl:'https://x', storage: storage, client: MockClient((req) async {
      if (req.url.path.endsWith('/refresh')) return http.Response('{"error":"Invalid"}', 401);
      return http.Response('{}', 404);
    }));
    final ok = await s.restoreSession();
    expect(ok, false);
    expect(s.isAuthenticated, false);
    expect(s.user, isNull);
    expect(await storage.read(key: 'motri.backend.refresh_token'), isNull);
    s.dispose();
  });
}
