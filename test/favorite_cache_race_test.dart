import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/seller_trust_cache.dart';

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

const a = '00000000-0000-4000-8000-000000000001',
    b = '00000000-0000-4000-8000-000000000002';

String _authResponse(String id) => jsonEncode({
      'authenticated': true,
      'access_token': 'a-$id',
      'refresh_token': 'r-$id',
      'expires_in': 3600,
      'user': {'id': id, 'email': '$id@example.com', 'is_admin': false}
    });

void main() {
  late BackendAuthSession session;
  late TrustCache cache;
  late Future<List<Map<String, dynamic>>> Function(String userId) readFavorites;
  final requests = <String>[];

  setUp(() async {
    requests.clear();
    readFavorites = (userId) async => <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/login')) {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final id = body['email'] == 'b@example.com' ? b : a;
        return http.Response(_authResponse(id), 200,
            headers: {'content-type': 'application/json'});
      }
      if (req.url.path.endsWith('/logout')) {
        return http.Response(jsonEncode({'ok': true}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    session = BackendAuthSession(
        baseUrl: 'https://example.test', client: client, storage: _MemStorage());
    await session.login(email: 'a@example.com', password: 'fixture');
    cache = TrustCache(
      session,
      loadFavoriteRows: (userId) {
        requests.add(userId);
        return readFavorites(userId);
      },
      loadSellerReviews: (_) async => [],
      loadSellerVerifications: (_) async => [],
    );
  });

  tearDown(() async {
    cache.dispose();
    session.dispose();
  });

  test('late bulk read cannot overwrite a confirmed write', () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    readFavorites = (_) => gate.future;
    final pending = cache.preloadFavorites();
    await Future<void>.delayed(Duration.zero);
    cache.setFavorite('car', true);
    gate.complete([]);
    await pending;
    expect(cache.isFavorite('car'), isTrue);
    expect(requests, hasLength(1));
  });

  test(
      'reset rejects old data and an old completion cannot clear a newer request',
      () async {
    final first = Completer<List<Map<String, dynamic>>>(),
        second = Completer<List<Map<String, dynamic>>>();
    readFavorites = (_) => requests.length == 1 ? first.future : second.future;
    final old = cache.preloadFavorites();
    await Future<void>.delayed(Duration.zero);
    cache.reset();
    final current = cache.preloadFavorites();
    await Future<void>.delayed(Duration.zero);
    first.complete([
      {'car_id': 'old'}
    ]);
    await old;
    final joined = cache.preloadFavorites();
    expect(requests, hasLength(2));
    second.complete([
      {'car_id': 'new'}
    ]);
    await Future.wait([current, joined]);
    expect(cache.isFavorite('old'), isFalse);
    expect(cache.isFavorite('new'), isTrue);
  });

  test('account changes invalidate old requests and write tokens', () async {
    final first = Completer<List<Map<String, dynamic>>>(),
        second = Completer<List<Map<String, dynamic>>>();
    readFavorites = (userId) => userId == a ? first.future : second.future;
    final old = cache.preloadFavorites();
    final token = cache.beginFavoriteChange('car')!;
    await session.logout();
    await session.login(email: 'b@example.com', password: 'fixture');
    await Future<void>.delayed(Duration.zero);
    final newToken = cache.beginFavoriteChange('car')!;
    expect(cache.favoriteChangeCurrent('car', token), isFalse);
    cache.endFavoriteChange('car', token);
    expect(cache.favoriteBusy('car'), isTrue);
    first.complete([
      {'car_id': 'private-a'}
    ]);
    await old;
    second.complete([
      {'car_id': 'private-b'}
    ]);
    await cache.preloadFavorites();
    expect(cache.isFavorite('private-a'), isFalse);
    expect(cache.isFavorite('private-b'), isTrue);
    cache.endFavoriteChange('car', newToken);
  });

  test('auth required after successful load preserves previous IDs and loaded state', () async {
    readFavorites = (_) async => [
          {'car_id': 'keep-me'}
        ];
    await cache.preloadFavorites();
    expect(cache.isFavorite('keep-me'), isTrue);
    expect(cache.favoritesLoaded, isTrue);

    // Next attempt fails with auth required (same account, no reset) — must preserve.
    readFavorites = (_) async =>
        throw const BackendApiException('Backend authentication required');
    await cache.preloadFavorites();

    // Must NOT become a confirmed empty favorites result.
    expect(cache.isFavorite('keep-me'), isTrue);
    expect(cache.favoritesLoaded, isTrue);
    expect(cache.favoriteIdsSnapshot(), contains('keep-me'));
  });

  test('first load with auth required does not record successful empty load', () async {
    readFavorites = (_) async =>
        throw const BackendApiException('Backend authentication required');
    await cache.preloadFavorites();

    expect(cache.favoritesLoaded, isFalse);
    expect(cache.favoriteIdsSnapshot(), isEmpty);
    // No confirmed "no favorites" state; unknown remains unknown.
  });

  test('successful empty HTTP response records empty-loaded correctly', () async {
    readFavorites = (_) async => <Map<String, dynamic>>[];
    await cache.preloadFavorites();

    expect(cache.favoritesLoaded, isTrue);
    expect(cache.favoriteIdsSnapshot(), isEmpty);
    expect(cache.isFavorite('any'), isFalse);
  });

  test('network/503 error does not clear cached favorite IDs', () async {
    readFavorites = (_) async => [
          {'car_id': 'cached'}
        ];
    await cache.preloadFavorites();
    expect(cache.isFavorite('cached'), isTrue);

    // Next attempt fails transiently (same account, no reset) — preserve IDs.
    readFavorites = (_) async =>
        throw const BackendApiException('server unavailable', statusCode: 503);
    await cache.preloadFavorites();

    // Transient failure must not wipe known IDs or create a confirmed empty state.
    expect(cache.isFavorite('cached'), isTrue);
    expect(cache.favoriteIdsSnapshot(), contains('cached'));
  });

  test('auth-required in-flight result cannot clear data after account change', () async {
    final gate = Completer<List<Map<String, dynamic>>>();
    readFavorites = (userId) async {
      if (userId == a) return gate.future;
      return [
        {'car_id': 'b-only'}
      ];
    };
    final old = cache.preloadFavorites();
    await Future<void>.delayed(Duration.zero);
    await session.logout();
    await session.login(email: 'b@example.com', password: 'fixture');
    await cache.preloadFavorites();
    expect(cache.isFavorite('b-only'), isTrue);

    // Old account request completes as auth-required; must not affect account B.
    gate.completeError(
        const BackendApiException('Backend authentication required'));
    await old;
    expect(cache.isFavorite('b-only'), isTrue);
    expect(cache.isFavorite('private-a'), isFalse);
  });
}
