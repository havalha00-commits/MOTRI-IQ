import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

const oldUser = '00000000-0000-4000-8000-000000000001';
const newUser = '00000000-0000-4000-8000-000000000002';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
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
  }) async {
    _values.remove(key);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  var nextUser = oldUser;
  var empty = false;
  Completer<void>? readGate, patchGate, carGate;
  final reads = <Uri>[];
  final apiReads = <http.Request>[];
  var patches = 0;
  Future<void> signIn(String id) async {
    nextUser = id;
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
    await backendAuthSession.login(
      email: 'fixture@example.com',
      password: 'fixture',
    );
  }

  Future<void> signOut() async {
    await supabase.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          Object? body = [];
          final path = request.url.path;
          if (path == '/auth/v1/token') {
            final claims = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': nextUser,
                  'role': 'authenticated',
                  'exp': DateTime.now()
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch ~/
                      1000
                })))
                .replaceAll('=', '');
            final signature =
                base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$claims.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': nextUser,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
            body = Map<String, dynamic>.from(body as Map)
              ..['access_token'] = '$claims.$signature';
          } else if (path.startsWith('/rest/v1/')) {
            final actor = nextUser;
            final label = actor == newUser ? 'NEW' : 'OLD';
            if (request.method == 'PATCH') {
              patches++;
              await patchGate?.future;
            } else {
              reads.add(request.url);
              await readGate?.future;
              if (path.endsWith('/cars_public')) await carGate?.future;
              body = empty
                  ? []
                  : switch (path.split('/').last) {
                      'activity_notifications' => [
                          {
                            'id': 'notice-$actor',
                            'user_id': actor,
                            'title': '$label Notice',
                            'body': '$label private notification',
                            'notification_type': 'new_message',
                            'offer_id': 'offer-$actor',
                            'read_at': null
                          }
                        ],
                      'car_alerts' => [
                          {
                            'id': 'alert-$actor',
                            'user_id': actor,
                            'car_id': 'car-1',
                            'brand': '$label Car',
                            'model': 'Model',
                            'price': 25000,
                            'read_at': null
                          }
                        ],
                      'car_offers' => [
                          {
                            'id': 'offer-$actor',
                            'buyer_id': actor,
                            'seller_id': 'seller-1',
                            'status': 'accepted',
                            'car_title': '$label Offer',
                            'offer_price': 25000,
                            'car_offer_messages': [
                              {
                                'body': '$label Message',
                                'created_at': '2026-10-22T10:00:00Z',
                                'sender_id': actor
                              }
                            ]
                          }
                        ],
                      'user_follows' => [
                          {
                            'id': 'follow-$actor',
                            'follower_id': actor,
                            'followed_id': 'seller-1'
                          }
                        ],
                      'app_usernames' => {'username': '$label Member'},
                      'profiles' => [
                          {'id': 'seller-1', 'full_name': '$label Seller'}
                        ],
                      'seller_reviews' => [
                          {
                            'id': 'review-$actor',
                            'reviewer_id': actor,
                            'seller_id': 'seller-1',
                            'rating': 4,
                            'comment': '$label Review'
                          }
                        ],
                      'seller_showrooms' => [
                          {
                            'seller_id': 'seller-1',
                            'showroom_name': '$label Showroom'
                          }
                        ],
                      'favorites' => [
                          {
                            'car_id': 'car-1',
                            'item_type': 'car',
                            'item_id': 'car-1'
                          }
                        ],
                      'cars_public' => [
                          {
                            'id': 'car-1',
                            'brand': '$label Car',
                            'model': 'Model',
                            'price': 25000
                          }
                        ],
                      _ => [],
                    };
            }
          }
          return http.Response(jsonEncode(body), 200,
              request: request, headers: {'content-type': 'application/json'});
        }));
    backendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async {
        final userId = nextUser;
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'access_token': 'backend-access-$userId',
              'refresh_token': 'backend-refresh-$userId',
              'expires_in': 3600,
              'user': {
                'id': userId,
                'email': 'fixture@example.com',
                'username': 'fixture_user',
                'full_name': 'Fixture Member',
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200, request: request);
      }),
    );
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendAccessToken: () => backendAuthSession.accessToken,
      backendAccessTokenAsync: () => backendAuthSession.validAccessToken(),
      client: MockClient((request) async {
        apiReads.add(request);
        final path = request.url.path;
        final userId = nextUser;
        final label = userId == newUser ? 'NEW' : 'OLD';
        Object? data = [];
        if (request.method == 'PATCH') {
          patches++;
          await patchGate?.future;
          data = <String, dynamic>{};
        } else {
          await readGate?.future;
          if (path.endsWith('/cars/by-ids')) await carGate?.future;
          if (!empty) {
            if (path.endsWith('/activity/notifications')) {
              data = [
                {
                  'id': 'notice-$userId',
                  'user_id': userId,
                  'title': '$label Notice',
                  'body': '$label private notification',
                  'notification_type': 'new_message',
                  'offer_id': 'offer-$userId',
                  'read_at': null,
                }
              ];
            } else if (path.endsWith('/activity/car-alerts')) {
              data = [
                {
                  'id': 'alert-$userId',
                  'user_id': userId,
                  'car_id': 'car-1',
                  'brand': '$label Car',
                  'model': 'Model',
                  'price': 25000,
                  'read_at': null,
                }
              ];
            } else if (path.endsWith('/offers/buyer') ||
                path.endsWith('/offers/conversations')) {
              data = [
                {
                  'id': 'offer-$userId',
                  'buyer_id': userId,
                  'seller_id': 'seller-1',
                  'status': 'accepted',
                  'car_title': '$label Offer',
                  'offer_price': 25000,
                  'car_offer_messages': [
                    {
                      'body': '$label Message',
                      'created_at': '2026-10-22T10:00:00Z',
                      'sender_id': userId,
                    }
                  ],
                }
              ];
            } else if (path.endsWith('/sellers/reviews')) {
              data = [
                {
                  'id': 'review-$userId',
                  'reviewer_id': userId,
                  'seller_id': 'seller-1',
                  'rating': 4,
                  'comment': '$label Review',
                }
              ];
            } else if (path.endsWith('/profile/me')) {
              data = {
                'id': userId,
                'display_name': '$label Member',
                'username': '$label Member',
                'email': 'fixture@example.com',
              };
            } else if (path.endsWith('/favorites')) {
              data = [
                {'car_id': 'car-1', 'item_type': 'car', 'item_id': 'car-1'}
              ];
            } else if (path.endsWith('/cars/by-ids')) {
              data = [
                {
                  'id': 'car-1',
                  'brand': '$label Car',
                  'model': 'Model',
                  'price': 25000,
                }
              ];
            }
          }
        }
        return http.Response(
          jsonEncode({'success': true, 'data': data}),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  });
  setUp(() async {
    readGate = patchGate = carGate = null;
    reads.clear();
    apiReads.clear();
    patches = 0;
    empty = false;
    appLocaleNotifier.value = AppLocale.en;
    await signIn(oldUser);
  });
  Future<void> mount(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(Brightness.light), home: page));
    await frames(tester);
  }

  final pages = <String, Widget>{
    'notifications': const ActivityNotificationsPage(),
    'alerts': const AlertsPage(),
    'sent offers': const MySentOffersPage(),
    'follows': const MyFollowsPage(),
    'messages': const MyMessagesPage(),
    'reviews': const MyReviewsPage(),
    'favorites': const FavoritesPage(),
    'profile': const UserProfilePage(),
  };
  for (final entry in pages.entries) {
    testWidgets('${entry.key} refreshes scoped rows after switching accounts',
        (tester) async {
      await mount(tester, entry.value);
      expect(find.textContaining('OLD'), findsWidgets);
      await tester.runAsync(() => signIn(newUser));
      await frames(tester);
      expect(find.textContaining('OLD'), findsNothing);
      expect(find.textContaining('NEW'), findsWidgets);
      if (entry.key == 'follows') {
        final scoped = reads.where((u) => u.path.endsWith('/user_follows'));
        expect(scoped.last.query, contains(newUser));
      } else {
        final latest = apiReads.last;
        expect(
            latest.headers['authorization'], 'Bearer backend-access-$newUser');
      }
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '${entry.key} rejects late rows after sign-out without secondary reads',
        (tester) async {
      readGate = Completer<void>();
      await mount(tester, entry.value);
      await tester.runAsync(signOut);
      readGate!.complete();
      await frames(tester);
      expect(find.textContaining('OLD'), findsNothing);
      expect(
          find.text(t(entry.key == 'favorites'
              ? 'account_login_to_see_favs'
              : 'login_required_first')),
          findsOneWidget);
      expect(
          reads.where((u) => ['profiles', 'seller_showrooms']
              .contains(u.path.split('/').last)),
          isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'pending notification read cannot open an old conversation after sign-out',
      (tester) async {
    await mount(tester, const ActivityNotificationsPage());
    patchGate = Completer<void>();
    await tester.tap(find.text('OLD Notice'));
    await frames(tester);
    expect(patches, 1);
    await tester.runAsync(signOut);
    patchGate!.complete();
    await frames(tester);
    expect(reads.where((u) => u.path.endsWith('/car_offers')), isEmpty);
    expect(find.byType(CarOfferChatPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'pending alert lookup stops marking read and navigation after sign-out',
      (tester) async {
    await mount(tester, const AlertsPage());
    carGate = Completer<void>();
    await tester.tap(find.textContaining('OLD Car'));
    await frames(tester);
    await tester.runAsync(signOut);
    carGate!.complete();
    await frames(tester);
    expect(patches, 0);
    expect(find.byType(CarDetailsPage), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final entry in pages.entries.where((e) =>
      ['sent offers', 'messages', 'reviews', 'favorites'].contains(e.key))) {
    testWidgets('${entry.key} empty state refresh discovers new rows',
        (tester) async {
      empty = true;
      await mount(tester, entry.value);
      expect(find.textContaining('OLD'), findsNothing);
      expect(find.text(t('alerts_update')), findsOneWidget);
      empty = false;
      await tester.tap(find.text(t('alerts_update')));
      await frames(tester);
      expect(find.textContaining('OLD'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
}
