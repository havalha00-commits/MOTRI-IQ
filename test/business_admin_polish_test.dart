import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/auth/auth_capabilities.dart';

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
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final requests = <Uri>[];
  const newest = 'unused';
  var failRead = false,
      denied = false,
      failPatch = false,
      noop = false,
      badPackage = false;
  var patches = 0;
  Map<String, dynamic>? update;
  var row = <String, dynamic>{};
  Completer<void>? gate, readGate;
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
    const uid = '00000000-0000-4000-8000-000000000001';
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': uid,
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
          requests.add(request.url);
          Object? body = [];
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    testBackendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => supabase.auth.currentSession?.accessToken,
      client: MockClient((request) async {
        requests.add(request.url);
        if (request.url.path.endsWith('/business-ads/admin')) {
          await readGate?.future;
          if (failRead) {
            return http.Response('{"error":"private diagnostic"}', 500);
          }
          if (denied) {
            return http.Response(
                '{"error":"Administrator access required"}', 403);
          }
          final statuses =
              request.url.queryParameters['statuses']?.split(',') ?? [];
          final rows = statuses.contains(row['status']) ? [row] : [];
          return http.Response(
            jsonEncode({'success': true, 'data': rows}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/decision')) {
          patches++;
          update = Map<String, dynamic>.from(jsonDecode(request.body));
          await gate?.future;
          if (failPatch) {
            return http.Response('{"error":"private diagnostic"}', 500);
          }
          if (noop || badPackage && update!['status'] == 'approved') {
            return http.Response('{"error":"decision was not applied"}', 409);
          }
          if (update!['payment'] == true) {
            row['payment_status'] = update!['status'];
          } else if (update!['status'] == 'approved') {
            row['status'] = 'approved';
            row['payment_status'] = 'paid';
          } else {
            row['status'] = update!['status'];
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'id': row['id'],
                'status': row['status'],
                'payment_status': row['payment_status'],
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"error":"not found"}', 404);
      }),
    );
    backendApi = testBackendApi;
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
                'id': uid,
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
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
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
    requests.clear();
    failRead = denied = failPatch = noop = badPackage = false;
    patches = 0;
    update = null;
    gate = readGate = null;
    row = {
      'id': 'ad-1',
      'business_name':
          'MOTRI automotive showroom with a very long business name',
      'status': 'pending',
      'payment_status': 'unpaid',
      'package_id': 'package-1',
      'category': 'Automotive service category with a long name',
      'governorate': 'Long province name',
      'created_at': '2026-10-21T00:00:00Z'
    };
    SharedPreferences.setMockInitialValues({
      'search_history': [newest, 'Older query', 'Older query', '']
    });
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
    darkModeNotifier.value = ThemeMode.light;
  });
  tearDownAll(() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
    backendApi = oldBackendApi;
    backendAuthSession = oldBackendAuthSession;
    testBackendApi.close();
    testBackendAuthSession.dispose();
  });
  Future<void> mount(WidgetTester tester, Widget page,
      {bool dark = false}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = dark;
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => AppStringsScope(
                locale: locale,
                child: AuthCapabilitiesScope(
                    loader: () async => const AuthCapabilitiesResult.ready(
                        AuthCapabilities(
                            phoneOtpEnabled: true, emailEnabled: true)),
                    child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: const TextScaler.linear(1.6)),
                        child: child!))),
            home: page)));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(find.text(t(key)), 180);
    await Scrollable.ensureVisible(tester.element(find.text(t(key))),
        alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(find.text(t(key)));
    await frames(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text(t('ui_business_confirm')));
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('$locale business moderation dark=$dark large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, const AdminBusinessAdsPage(), dark: dark);
        expect(find.text(row['business_name']), findsOneWidget);
        expect(
            tester.widget<Text>(find.text(row['business_name'])).textDirection,
            TextDirection.ltr);
        await tester.scrollUntilVisible(find.text(t('ad_view')), 150);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, 700));
        await tester.pumpAndSettle();
        await currentTypographyCheckpoint(tester, 'BUSINESS_ADMIN');
        await tapAction(tester, 'offer_accept');
        final title = find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(row['business_name']));
        expect(tester.widget<Text>(title).textDirection, TextDirection.ltr);
        expect(
            find.descendant(
                of: find.byType(AlertDialog), matching: find.text('ad-1')),
            findsOneWidget);
        await currentTypographyCheckpoint(tester, 'BUSINESS_ADMIN_APPROVE');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        await tapAction(tester, 'payment_confirm');
        await currentTypographyCheckpoint(tester, 'BUSINESS_ADMIN_PAYMENT');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(patches, 0);
        if (locale == AppLocale.en &&
            dark &&
            const bool.fromEnvironment('UI_BUSINESS_ADMIN_REVIEW_HOLD')) {
          debugPrint('UI_BUSINESS_ADMIN_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        await finish(tester);
      });
    }
  }
  testWidgets('denied differs from access failure and retry', (tester) async {
    failRead = true;
    await mount(tester, const AdminBusinessAdsPage());
    expect(find.text(t('ui_retry')), findsOneWidget);
    failRead = false;
    denied = true;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(
      requests.where((u) => u.path.endsWith('/business-ads/admin')).length,
      2,
    );
    await finish(tester);
  });
  testWidgets('failed ads load retries and filter labels follow live locale',
      (tester) async {
    failRead = true;
    await mount(tester, const AdminBusinessAdsPage());
    failRead = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    appLocaleNotifier.value = AppLocale.en;
    await frames(tester);
    expect(find.text('Ad status'), findsOneWidget);
    expect(find.text(t('ad_status_pending')), findsWidgets);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('common_all')).last);
    await frames(tester);
    expect(
        requests.where((u) =>
            u.path.endsWith('/business-ads/admin') &&
            u.queryParameters['statuses']!.contains('paused')),
        isNotEmpty);
    await finish(tester);
  });
  testWidgets('approval is confirmed and the server applies the package period',
      (tester) async {
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_accept');
    expect(find.text(t('ui_business_approve_confirm')), findsOneWidget);
    expect(patches, 0);
    await confirm(tester);
    expect(patches, 1);
    expect(update!['status'], 'approved');
    expect(update!['payment'], false);
    expect(update!['expected_status'], 'pending');
    expect(find.text(t('ui_business_updated')), findsOneWidget);
    final patch = requests.lastWhere((u) => u.path.endsWith('/decision'));
    expect(patch.path, endsWith('/admin/ad-1/decision'));
    await finish(tester);
  });
  testWidgets('cancel rejection leaves ad unchanged', (tester) async {
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_reject');
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(patches, 0);
    await finish(tester);
  });
  for (final noChange in [false, true]) {
    testWidgets('failed/noop=$noChange decision retains row and allows retry',
        (tester) async {
      failPatch = !noChange;
      noop = noChange;
      await mount(tester, const AdminBusinessAdsPage());
      await tapAction(tester, 'offer_reject');
      await confirm(tester);
      expect(find.text(t('ui_business_update_failed')), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      ScaffoldMessenger.of(tester.element(find.byType(AdminBusinessAdsPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      failPatch = noop = false;
      await tapAction(tester, 'offer_reject');
      await confirm(tester);
      expect(row['status'], 'rejected');
      await finish(tester);
    });
  }
  testWidgets('missing package duration prevents partial approval',
      (tester) async {
    badPackage = true;
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_accept');
    await confirm(tester);
    expect(patches, 1);
    expect(find.text(t('ui_business_update_failed')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('payment confirmation changes only payment status',
      (tester) async {
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'payment_confirm');
    await confirm(tester);
    expect(update, {
      'payment': true,
      'status': 'paid',
      'expected_status': 'pending',
      'expected_payment_status': 'unpaid',
    });
    expect(row['status'], 'pending');
    await finish(tester);
  });
  testWidgets('pending decision guards duplicates and safe disposal',
      (tester) async {
    gate = Completer<void>();
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_reject');
    await confirm(tester);
    expect(patches, 1);
    final action = tester
        .widget<TextButton>(find.widgetWithText(TextButton, t('offer_reject')));
    expect(action.onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  for (final initial in ['approved', 'active', 'paused']) {
    testWidgets('$initial has the appropriate state transition',
        (tester) async {
      row['status'] = initial;
      row['payment_status'] = 'paid';
      await mount(tester, const AdminBusinessAdsPage());
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      final label = {
        'approved': 'ad_status_approved',
        'active': 'ad_status_active',
        'paused': 'ad_status_stopped'
      }[initial]!;
      await tester.tap(find.text(t(label)).last);
      await frames(tester);
      await tapAction(
          tester, initial == 'active' ? 'common_stop' : 'ui_business_activate');
      await confirm(tester);
      expect(update!['status'], initial == 'active' ? 'paused' : 'active');
      expect(update!.containsKey('payment_status'), isFalse);
      await finish(tester);
    });
  }
  for (final stage in ['rows']) {
    testWidgets('business admin late $stage cannot restore private ads',
        (tester) async {
      final pending = Completer<void>();
      readGate = pending;
      await mount(tester, const AdminBusinessAdsPage());
      await signOutAccount(tester);
      await frames(tester);
      pending.complete();
      await frames(tester);
      expect(find.text(t('admin_only_notice')), findsOneWidget);
      expect(find.text(row['business_name']), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  for (final payment in [false, true]) {
    testWidgets(
        'business admin confirmation payment=$payment rejects replaced session',
        (tester) async {
      await mount(tester, const AdminBusinessAdsPage());
      await tapAction(tester, payment ? 'payment_confirm' : 'offer_accept');
      await signOutAccount(tester);
      await frames(tester);
      await signInAccount(tester);
      await frames(tester);
      await confirm(tester);
      expect(patches, 0);
      expect(find.text(t('ui_business_updated')), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('business admin logout during decision prevents success',
      (tester) async {
    gate = Completer<void>();
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_accept');
    await confirm(tester);
    expect(requests.any((u) => u.path.endsWith('/decision')), isTrue);
    await signOutAccount(tester);
    await frames(tester);
    gate!.complete();
    await frames(tester);
    expect(patches, 1);
    expect(find.text(t('ui_business_updated')), findsNothing);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('business admin late update cannot refresh or announce success',
      (tester) async {
    gate = Completer<void>();
    await mount(tester, const AdminBusinessAdsPage());
    await tapAction(tester, 'offer_reject');
    await confirm(tester);
    expect(patches, 1);
    await signOutAccount(tester);
    await frames(tester);
    final before = requests.length;
    gate!.complete();
    await frames(tester);
    expect(requests.length, before);
    expect(find.text(t('ui_business_updated')), findsNothing);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('business admin all-status chain stops after logout',
      (tester) async {
    await mount(tester, const AdminBusinessAdsPage());
    readGate = Completer<void>();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('common_all')).last);
    await frames(tester);
    final before =
        requests.where((u) => u.path.endsWith('/business-ads/admin')).length;
    await signOutAccount(tester);
    await frames(tester);
    readGate!.complete();
    await frames(tester);
    expect(requests.where((u) => u.path.endsWith('/business-ads/admin')).length,
        before);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        'pending');
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code} business admin preview stays locked after session replacement',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester, const AdminBusinessAdsPage(),
          dark: locale == AppLocale.ku);
      await tapAction(tester, 'ad_view');
      expect(find.byType(BusinessAdDetailsPage), findsOneWidget);
      await signOutAccount(tester);
      await frames(tester);
      expect(find.byType(BusinessAdDetailsPage), findsNothing);
      expect(find.byKey(const ValueKey('account_scoped_view_expired')),
          findsOneWidget);
      await currentTypographyCheckpoint(tester, 'BUSINESS_ADMIN_EXPIRED');
      await signInAccount(tester);
      await frames(tester);
      expect(find.byType(BusinessAdDetailsPage), findsNothing);
      expect(find.byKey(const ValueKey('account_scoped_view_expired')),
          findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await frames(tester);
      await tapAction(tester, 'ad_view');
      expect(find.byType(BusinessAdDetailsPage), findsOneWidget);
      expect(find.byKey(const ValueKey('account_scoped_view_expired')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
}
