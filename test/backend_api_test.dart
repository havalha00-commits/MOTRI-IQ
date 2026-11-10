import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

BackendApi _api({
  required MockClient client,
  // backendOnly=true path
  String? backendOnlyToken,
  // backendOnly=false path (caller controls priority, as main.dart does)
  String? defaultToken,
}) {
  return BackendApi(
    baseUrl: 'https://backend.test',
    client: client,
    backendAccessToken: () => backendOnlyToken,
    backendAccessTokenAsync: () async => backendOnlyToken,
    accessToken: () => defaultToken,
    accessTokenAsync: () async => defaultToken,
  );
}

void _expectNoTokenLeak(http.BaseRequest req, String mustNotAppear) {
  final headerDump = req.headers.entries
      .where((e) => e.key.toLowerCase() != 'authorization')
      .map((e) => '${e.key}:${e.value}')
      .join(';');
  expect(headerDump, isNot(contains(mustNotAppear)),
      reason: 'token leaked in non-Authorization headers');
  expect(req.url.toString(), isNot(contains(mustNotAppear)),
      reason: 'token leaked in URL/query');
}

void main() {
  group('BackendApi token isolation (G10.12)', () {
    test('anonymous GET sends no token and does not resolve a session', () async {
      var tokenReads = 0;
      late http.Request seen;
      final api = BackendApi(
        baseUrl: 'https://backend.test',
        backendAccessToken: () {
          tokenReads++;
          return 'backend.jwt.token';
        },
        accessToken: () {
          tokenReads++;
          return 'supabase.jwt.token';
        },
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'success': true, 'data': []}), 200);
        }),
      );

      final response = await api.get('business-ads/active', anonymous: true);

      expect(response, {'success': true, 'data': []});
      expect(tokenReads, 0);
      expect(seen.headers.containsKey('authorization'), isFalse);
    });

    test('backendOnly=true GET sends Backend JWT only', () async {
      late http.Request seen;
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.get('profile/me', backendOnly: true);

      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/profile/me');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.headers['authorization'], isNot(contains('supabase')));
      expect(seen.headers.values.join(' '), isNot(contains('supabase.jwt.token')));
      expect(seen.body, isEmpty);
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
      _expectNoTokenLeak(seen, 'backend.jwt.token');
    });

    test('backendOnly=true POST sends Backend JWT only', () async {
      late http.Request seen;
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.post('profile/username',
          body: {'username': 'alice'}, backendOnly: true);

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/profile/username');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.headers.values.join(' '), isNot(contains('supabase.jwt.token')));
      expect(seen.body, isNot(contains('supabase.jwt.token')));
      expect(seen.body, isNot(contains('backend.jwt.token')));
      expect(jsonDecode(seen.body), {'username': 'alice'});
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
      _expectNoTokenLeak(seen, 'backend.jwt.token');
    });

    test('backendOnly=true PUT bytes sends Backend JWT only', () async {
      late http.Request seen;
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.putBytes('wallet/topups/t/receipt/upload',
          body: Uint8List.fromList([1, 2, 3, 4]),
          contentType: 'image/jpeg',
          backendOnly: true);

      expect(seen.method, 'PUT');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.headers.values.join(' '), isNot(contains('supabase.jwt.token')));
      expect(seen.bodyBytes, [1, 2, 3, 4]);
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
      _expectNoTokenLeak(seen, 'backend.jwt.token');
    });

    test(
        'backendOnly=true rejects locally when Backend JWT missing (even with Supabase JWT) and never hits transport',
        () async {
      var transportHits = 0;
      final api = _api(
        client: MockClient((req) async {
          transportHits++;
          return http.Response('{}', 500);
        }),
        backendOnlyToken: null,
        defaultToken: 'supabase.jwt.token',
      );

      await expectLater(
        api.get('profile/me', backendOnly: true),
        throwsA(isA<BackendApiException>().having(
            (e) => e.message, 'message', 'Backend authentication required')),
      );
      expect(transportHits, 0, reason: 'rejected request must not reach HTTP');
    });

    test(
        'backendOnly=true rejects locally for POST bytes when Backend JWT missing',
        () async {
      var transportHits = 0;
      final api = _api(
        client: MockClient((req) async {
          transportHits++;
          return http.Response('{}', 500);
        }),
        backendOnlyToken: '',
        defaultToken: 'supabase.jwt.token',
      );

      await expectLater(
        api.postBytes('wallet/topups/t/receipt/upload',
            body: Uint8List.fromList([9]),
            contentType: 'image/jpeg',
            backendOnly: true),
        throwsA(isA<BackendApiException>()),
      );
      expect(transportHits, 0);
    });

    test('backendOnly=false prefers Backend JWT when both available (main.dart wiring contract)',
        () async {
      late http.Request seen;
      // backendOnly=false uses accessToken*; main.dart sets accessToken* to
      // prefer backendAuthSession token then fallback to Supabase.
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.get('cars');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');

      await api.post('offers', body: {'x': 1});
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.body, isNot(contains('backend.jwt.token')));
    });

    test('backendOnly=false falls back to Supabase JWT when Backend missing (main.dart wiring contract)',
        () async {
      late http.Request seen;
      // main.dart accessToken fallback returns Supabase when backend absent.
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        backendOnlyToken: null,
        defaultToken: 'supabase.jwt.token',
      );

      await api.get('favorites');
      expect(seen.headers['authorization'], 'Bearer supabase.jwt.token');
      _expectNoTokenLeak(seen, 'supabase.jwt.token');

      await api.post('offers', body: {'x': 1});
      expect(seen.headers['authorization'], 'Bearer supabase.jwt.token');
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
    });

    // --- G10.16 (TEST-ONLY): favorites endpoint path, backendOnly contract ---
    test('G10.16 favorites GET with backendOnly=true sends Backend JWT only (no Supabase)', () async {
      late http.Request seen;
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'success': true, 'data': []}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.get('favorites', backendOnly: true);

      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/favorites');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.headers.values.join(' '), isNot(contains('supabase.jwt.token')));
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
      _expectNoTokenLeak(seen, 'backend.jwt.token');
    });

    test('G10.16 favorites PUT with backendOnly=true sends Backend JWT only (no Supabase)', () async {
      late http.Request seen;
      final api = _api(
        client: MockClient((req) async {
          seen = req;
          return http.Response(jsonEncode({'success': true}), 200);
        }),
        backendOnlyToken: 'backend.jwt.token',
        defaultToken: 'supabase.jwt.token',
      );

      await api.put('favorites/car-1', body: {'favorite': true}, backendOnly: true);

      expect(seen.method, 'PUT');
      expect(seen.url.path, '/api/favorites/car-1');
      expect(seen.headers['authorization'], 'Bearer backend.jwt.token');
      expect(seen.headers.values.join(' '), isNot(contains('supabase.jwt.token')));
      expect(seen.body, isNot(contains('supabase.jwt.token')));
      expect(jsonDecode(seen.body), {'favorite': true});
      _expectNoTokenLeak(seen, 'supabase.jwt.token');
      _expectNoTokenLeak(seen, 'backend.jwt.token');
    });

    test(
        'G10.16 favorites: Supabase JWT alone cannot satisfy backendOnly=true (rejects locally, no transport)',
        () async {
      var transportHits = 0;
      final api = _api(
        client: MockClient((req) async {
          transportHits++;
          return http.Response('{}', 500);
        }),
        backendOnlyToken: null,
        defaultToken: 'supabase.jwt.token',
      );

      await expectLater(
        api.get('favorites', backendOnly: true),
        throwsA(isA<BackendApiException>().having(
            (e) => e.message, 'message', 'Backend authentication required')),
      );
      expect(transportHits, 0, reason: 'Supabase-only token must not reach backend favorites');
    });

    test('G10.16 favorites: missing Backend JWT rejects locally before HTTP transport', () async {
      var transportHits = 0;
      final api = _api(
        client: MockClient((req) async {
          transportHits++;
          return http.Response('{}', 500);
        }),
        backendOnlyToken: null,
        defaultToken: null,
      );

      await expectLater(
        api.put('favorites/car-1', body: {'favorite': true}, backendOnly: true),
        throwsA(isA<BackendApiException>().having(
            (e) => e.message, 'message', 'Backend authentication required')),
      );
      expect(transportHits, 0);
    });
  });
}
