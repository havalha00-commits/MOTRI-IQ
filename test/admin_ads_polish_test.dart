import 'package:motri_iq/l10n/app_delegates.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/l10n/app_locale.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const offer = {
  'id': 'offer-1',
  'car_title': 'MOTRI automotive marketplace vehicle with a long model name'
};

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};

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
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  var admin = true, accessFails = false, deleteFails = false, deletes = 0;
  final failedTables = <String>{};
  final reads = <String, int>{};
  Completer<void>? deleteGate, accessGate;
  var data = <String, List<Map<String, dynamic>>>{};
  late BackendAuthSession oldBackendAuthSession;
  late BackendApi oldBackendApi;
  late BackendAuthSession testBackendAuthSession;
  late BackendApi testBackendApi;

  Future<void> signOutAccount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await backendAuthSession.logout();
      await supabase.auth.signOut(scope: SignOutScope.local);
    });
  }

  Future<void> signInAccount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await supabase.auth.signInWithPassword(
        email: 'fixture@example.com',
        password: 'fixture-only',
      );
      await backendAuthSession.login(
        email: 'fixture@example.com',
        password: 'fixture-only',
      );
    });
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    oldBackendAuthSession = backendAuthSession;
    oldBackendApi = backendApi;
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': userId,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final signature =
        base64Url.encode(List<int>.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          Object? body = [];
          var status = 200;
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': userId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
          } else if (request.url.path.endsWith('app_admins')) {
            await accessGate?.future;
            if (accessFails) {
              status = 400;
              body = {'message': 'Private access diagnostics'};
            } else {
              body = admin ? {'user_id': userId} : null;
            }
          } else if (request.url.path.endsWith('admin_delete_ad')) {
            deletes++;
            await deleteGate?.future;
            final params = jsonDecode(request.body) as Map;
            if (deleteFails) {
              body = {'ok': false, 'reason': 'forbidden'};
            } else {
              data[params['p_table']]
                  ?.removeWhere((r) => r['id'] == params['p_id']);
              body = {'ok': true, 'deleted': 1};
            }
          } else {
            final table = request.url.path.split('/').last;
            reads.update(table, (n) => n + 1, ifAbsent: () => 1);
            if (failedTables.contains(table)) {
              status = 400;
              body = {'message': 'Private table diagnostics'};
            } else {
              body = data[table] ?? [];
            }
          }
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
    testBackendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async => http.Response(
        jsonEncode({
          'authenticated': true,
          'access_token': 'fixture-access-token',
          'refresh_token': 'fixture-refresh-token',
          'expires_in': 3600,
          'user': {
            'id': userId,
            'email': 'fixture@example.com',
            'is_admin': true,
          },
        }),
        200,
        request: request,
      )),
    );
    await testBackendAuthSession.login(
      email: 'fixture@example.com',
      password: 'fixture-only',
    );
    backendAuthSession = testBackendAuthSession;
    testBackendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendAccessTokenAsync: testBackendAuthSession.validAccessToken,
      backendAccessToken: () => testBackendAuthSession.accessToken,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/sellers/admin/status')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'is_admin': admin},
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.contains('/market/admin/ads/')) {
          deletes++;
          await deleteGate?.future;
          final segments = request.url.path.split('/');
          final table = segments[segments.length - 2];
          final id = segments.last;
          if (deleteFails) {
            return http.Response(
              jsonEncode({'ok': false, 'reason': 'forbidden'}),
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          data[table]?.removeWhere((item) => item['id'] == id);
          return http.Response(
            jsonEncode({'ok': true, 'deleted': 1}),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"error":"not found"}', 404, request: request);
      }),
    );
    backendApi = testBackendApi;
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only');
    }
    if (backendAuthSession.user == null) {
      await backendAuthSession.login(
        email: 'fixture@example.com',
        password: 'fixture-only',
      );
    }
    admin = true;
    accessFails = false;
    deleteFails = false;
    deletes = 0;
    failedTables.clear();
    reads.clear();
    deleteGate = accessGate = null;
    data = {
      for (final table in ['cars', 'market_items', 'jobs'])
        table: [
          {
            'id': '$table-1',
            'title':
                'A long vehicle advertisement title with additional details that must remain readable',
            'governorate': 'A long governorate and city name',
            'price': 25000
          }
        ]
    };
  });
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);
  tearDownAll(() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
    backendApi = oldBackendApi;
    backendAuthSession = oldBackendAuthSession;
    testBackendApi.close();
    testBackendAuthSession.dispose();
  });
  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light, Widget? page}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = brightness == Brightness.dark;
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        theme: buildAppTheme(brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: page ?? const AdminAdsManagementPage()));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  Finder deleteButton() => find.byTooltip(t('admin_delete_ad')).first;
  testWidgets('state gap admin successful empty tables', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    data.updateAll((key, value) => <Map<String, dynamic>>[]);
    await mount(tester);
    expect(find.text(t('admin_ads_none')), findsWidgets);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    expect(find.text(t('admin_only_notice')), findsNothing);
    expect(find.text(t('ui_load_error_title')), findsNothing);
    expect(reads.keys, containsAll(['cars','market_items','jobs']));
    await currentTypographyCheckpoint(tester, 'GAP_ADMIN_EMPTY');
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${locale.code} admin ads populated $brightness large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(find.text(data['cars']!.first['title']), findsWidgets);
        await currentTypographyCheckpoint(tester, 'ADMIN_MANAGER');
        if (const bool.fromEnvironment('UI_ADMIN_MANAGER_REVIEW_HOLD') &&
            locale == AppLocale.en &&
            brightness == Brightness.dark) {
          debugPrint('UI_ADMIN_MANAGER_REVIEW_READY');
          await Future<void>.delayed(const Duration(seconds: 15));
        }
        await tester.tap(deleteButton());
        await frames(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(deletes, 0);
        await finish(tester);
      });
    }
  }
  testWidgets('initial delayed admin access shows loading before listings',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    accessGate = Completer<void>();
    await mount(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t('admin_only_notice')), findsNothing);
    expect(reads, isEmpty);
    await currentTypographyCheckpoint(tester, 'ADMIN_INITIAL_LOADING');
    accessGate!.complete();
    await frames(tester);
    expect(find.text(data['cars']!.first['title']), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  testWidgets('non-admin shows access state and skips listing reads',
      (tester) async {
    admin = false;
    await mount(tester);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(reads, isEmpty);
    await finish(tester);
  });
  testWidgets('failed access check has retry instead of claiming access denied',
      (tester) async {
    accessFails = true;
    await mount(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('admin_only_notice')), findsNothing);
    expect(find.textContaining('Private'), findsNothing);
    accessFails = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsWidgets);
    await finish(tester);
  });
  testWidgets('one failed table shows retry while successful sections remain',
      (tester) async {
    failedTables.add('cars');
    await mount(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(reads['market_items'], 1);
    expect(reads['jobs'], 1);
    expect(find.textContaining('Private'), findsNothing);
    failedTables.clear();
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('ui_load_error_title')), findsNothing);
    expect(reads['cars'], 2);
    await finish(tester);
  });
  testWidgets('confirmed deletion prevents duplicates and removes only target',
      (tester) async {
    deleteGate = Completer<void>();
    await mount(tester);
    await tester.tap(deleteButton());
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(deletes, 1);
    final buttons = tester
        .widgetList<IconButton>(find.byType(IconButton))
        .where((b) => b.tooltip == t('admin_delete_ad'));
    expect(buttons.every((b) => b.onPressed == null), isTrue);
    deleteGate!.complete();
    await frames(tester);
    expect(data['cars'], isEmpty);
    expect(data['market_items'], hasLength(1));
    expect(find.text(t('admin_delete_ad_done')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('failed deletion keeps row and shows localized feedback',
      (tester) async {
    deleteFails = true;
    await mount(tester);
    await tester.tap(deleteButton());
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(data['cars'], hasLength(1));
    expect(find.text(t('admin_delete_ad_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    await finish(tester);
  });
  testWidgets('closing manager during delete safely ignores completion',
      (tester) async {
    deleteGate = Completer<void>();
    await mount(tester);
    await tester.tap(deleteButton());
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    await finish(tester);
    deleteGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'delete confirmation ${locale.code} dark=$dark large text identifies target',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester,
            brightness: dark ? Brightness.dark : Brightness.light);
        await tester.tap(deleteButton());
        await frames(tester);
        expect(
            find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text(data['cars']!.first['title'] as String)),
            findsOneWidget);
        expect(
            find.descendant(
                of: find.byType(AlertDialog),
                matching: find.text(t('section_cars'))),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'ADMIN_DELETE_CONFIRM');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(deletes, 0);
        await finish(tester);
      });
    }
  }
  testWidgets(
      'account loss during confirmation prevents deletion and hides admin rows',
      (tester) async {
    await mount(tester);
    await tester.tap(deleteButton());
    await frames(tester);
    await signOutAccount(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(deletes, 0);
    expect(find.text(t('ui_business_session_changed')), findsOneWidget);
    expect(find.byType(ExpansionTile), findsNothing);
    expect(find.text(data['cars']!.first['title'] as String), findsNothing);
    await finish(tester);
  });
  testWidgets('account loss during deletion cannot announce success',
      (tester) async {
    deleteGate = Completer<void>();
    await mount(tester);
    await tester.tap(deleteButton());
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(deletes, 1);
    await signOutAccount(tester);
    deleteGate!.complete();
    await frames(tester);
    expect(find.text(t('admin_delete_ad_done')), findsNothing);
    expect(find.text(t('ui_business_session_changed')), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'late access response after account loss cannot read listing tables',
      (tester) async {
    accessGate = Completer<void>();
    await mount(tester);
    await signOutAccount(tester);
    accessGate!.complete();
    await frames(tester);
    for (final table in ['cars', 'market_items', 'jobs']) {
      expect(reads[table] ?? 0, 0);
    }
    expect(find.text(t('ui_business_session_changed')), findsOneWidget);
    await finish(tester);
  });  testWidgets('car detail rejects late admin access after logout', (tester) async {
    accessGate = Completer<void>();
    await mount(tester, page: const CarDetailsPage(car: {'id': 'car-1', 'brand': 'Toyota', 'model': 'Camry', 'price': 25000}));
    await signOutAccount(tester);
    await frames(tester);
    accessGate!.complete();
    await frames(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    expect(deletes, 0);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('car detail confirmation cannot survive session replacement', (tester) async {
    await mount(tester, page: const CarDetailsPage(car: {'id': 'car-1', 'brand': 'Toyota', 'model': 'Camry', 'price': 25000}));
    await tester.tap(deleteButton());
    await frames(tester);
    expect(find.text(t('common_delete')), findsOneWidget);
    await signOutAccount(tester);
    await frames(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    await signInAccount(tester);
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(deletes, 0);
    expect(find.text(t('admin_delete_ad_done')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

}
