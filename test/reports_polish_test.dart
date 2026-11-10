import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/auth/auth_capabilities.dart';

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
      failAccess = false,
      denied = false,
      failPatch = false,
      noop = false;
  var failVerify = false,
      duplicate = false,
      noopVerify = false,
      failCar = false,
      available = false,
      empty = false;
  var patches = 0, verifications = 0;
  Map<String, dynamic>? update;
  var row = <String, dynamic>{};
  Map<String, dynamic>? userReportRow;
  Completer<void>? gate, accessGate, readGate, carGate;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
          if (request.url.path.endsWith('/app_admins')) {
            await accessGate?.future;
            if (failAccess) {
              return http.Response('{}', 500, request: request);
            }
            body = denied ? null : {'user_id': uid};
          }
          if (request.url.path.endsWith('/car_reports')) {
            if (request.method == 'PATCH') {
              patches++;
              update = Map<String, dynamic>.from(jsonDecode(request.body));
              await gate?.future;
              if (failPatch) {
                return http.Response('{"message":"private diagnostic"}', 500,
                    request: request);
              }
              if (noop) {
                body = [];
              } else {
                row.addAll(update!);
                body = [row];
              }
            } else {
              await readGate?.future;
              if (failRead) {
                return http.Response('{}', 500, request: request);
              }
              body = empty ? [] : [row];
            }
          }
          if (request.url.path.endsWith('/user_reports')) {
            if (request.method == 'PATCH') {
              patches++;
              update = Map<String, dynamic>.from(jsonDecode(request.body));
              if (!noop && userReportRow != null) {
                userReportRow!.addAll(update!);
                body = [userReportRow!];
              }
            } else {
              body = userReportRow == null ? [] : [userReportRow!];
            }
          }
          if (request.url.path.endsWith('/seller_verifications')) {
            if (request.method == 'POST') {
              verifications++;
              await gate?.future;
              if (duplicate) {
                return http.Response(
                    '{"code":"23505","message":"private diagnostic"}', 409,
                    headers: {'content-type': 'application/json'},
                    request: request);
              }
              if (failVerify) {
                return http.Response('{"message":"private diagnostic"}', 500,
                    request: request);
              }
              body = noopVerify
                  ? []
                  : [
                      {'seller_id': 'seller-1'}
                    ];
            }
          }
          if (request.url.path.endsWith('/cars')) {
            await carGate?.future;
            if (failCar) {
              return http.Response('{"message":"private diagnostic"}', 500,
                  request: request);
            }
            body = available
                ? {
                    'id': 'car-1',
                    'user_id': 'seller-1',
                    'brand': 'Toyota',
                    'model': 'Camry',
                    'price': 25000,
                    'year': 2024,
                    'images': <String>[],
                    'created_at': '2026-10-21T00:00:00Z'
                  }
                : null;
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only');
    }
    requests.clear();
    failRead = failAccess = denied = failPatch = noop = false;
    failVerify = duplicate = noopVerify = failCar = available = empty = false;
    patches = verifications = 0;
    update = null;
    userReportRow = null;
    gate = accessGate = readGate = carGate = null;
    row = {
      'id': 'report-1',
      'car_id': 'listing-00000000-0000-4000-8000-000000000001',
      'seller_id': 'seller-1',
      'status': 'open',
      'reason':
          'A detailed report about incorrect vehicle information with a long description for review',
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
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
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
    final finder = find.text(t(key));
    await tester.scrollUntilVisible(finder, 180,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await frames(tester);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text(t('ui_business_confirm')));
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('$locale reports dark=$dark large text', (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, const AdminDashboardPage(), dark: dark);
        expect(find.text(t('ui_report_listing_title')), findsOneWidget);
        expect(find.text(row['reason']), findsOneWidget);
        expect(
            tester.widget<EditableText>(find.text(row['reason'])).textDirection,
            TextDirection.ltr);
        expect(find.textContaining('2026-10-21T'), findsNothing);
        await tester.scrollUntilVisible(find.text(t('ad_status_reviewed')), 150,
            scrollable: find
                .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable))
                .first);
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(ListView), const Offset(0, 700));
        await tester.pumpAndSettle();
        await currentTypographyCheckpoint(tester, 'REPORTS');
        await tapAction(tester, 'ad_status_reviewed');
        await currentTypographyCheckpoint(tester, 'REPORT_CONFIRM');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        await tapAction(tester, 'seller_verify');
        await currentTypographyCheckpoint(tester, 'SELLER_CONFIRM');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(patches, 0);
        expect(verifications, 0);
        if (locale == AppLocale.en &&
            dark &&
            const bool.fromEnvironment('UI_REPORTS_REVIEW_HOLD')) {
          debugPrint('UI_REPORTS_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        await finish(tester);
      });
    }
  }
  testWidgets(
      'access failure retries to confirmed denied without reading reports',
      (tester) async {
    failAccess = true;
    await mount(tester, const AdminDashboardPage());
    failAccess = false;
    denied = true;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(requests.where((u) => u.path.endsWith('/car_reports')), isEmpty);
    await finish(tester);
  });
  testWidgets('read failure retries and empty refreshes', (tester) async {
    failRead = true;
    await mount(tester, const AdminDashboardPage());
    failRead = false;
    empty = true;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('report_no_reports')), findsOneWidget);
    empty = false;
    await tester.tap(find.byTooltip(t('alerts_update')));
    await frames(tester);
    expect(find.text(row['reason']), findsOneWidget);
    await finish(tester);
  });
  testWidgets('resolve requires confirmation and matches original status',
      (tester) async {
    await mount(tester, const AdminDashboardPage());
    await tapAction(tester, 'ad_status_reviewed');
    expect(patches, 0);
    expect(find.text(t('ui_report_change_confirm')), findsOneWidget);
    await confirm(tester);
    expect(update!['status'], 'resolved');
    expect(update!['reviewed_by'], isNotNull);
    expect(DateTime.parse(update!['reviewed_at']).isUtc, isTrue);
    final uri = requests.lastWhere((u) =>
        u.path.endsWith('/car_reports') && u.queryParameters.containsKey('id'));
    expect(uri.queryParameters['status'], 'eq.open');
    expect(find.text(t('ui_report_updated')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('reopening clears prior review fields', (tester) async {
    row.addAll({
      'status': 'resolved',
      'reviewed_by': 'admin-1',
      'reviewed_at': '2026-10-21T00:00:00Z'
    });
    await mount(tester, const AdminDashboardPage());
    await tapAction(tester, 'ad_reopen');
    await confirm(tester);
    expect(
        update, {'status': 'open', 'reviewed_by': null, 'reviewed_at': null});
    await finish(tester);
  });
  for (final noChange in [false, true]) {
    testWidgets('failed/noop=$noChange report decision keeps row retryable',
        (tester) async {
      failPatch = !noChange;
      noop = noChange;
      await mount(tester, const AdminDashboardPage());
      await tapAction(tester, 'ad_status_reviewed');
      await confirm(tester);
      expect(find.text(t('ui_report_update_failed')), findsOneWidget);
      expect(row['status'], 'open');
      expect(find.textContaining('private diagnostic'), findsNothing);
      ScaffoldMessenger.of(tester.element(find.byType(AdminDashboardPage)))
          .hideCurrentSnackBar();
      await tester.pumpAndSettle();
      failPatch = noop = false;
      await tapAction(tester, 'ad_status_reviewed');
      await confirm(tester);
      expect(row['status'], 'resolved');
      await finish(tester);
    });
  }
  testWidgets('verification cancellation performs no insert', (tester) async {
    await mount(tester, const AdminDashboardPage());
    await tapAction(tester, 'seller_verify');
    expect(find.text(t('ui_report_seller_id')), findsOneWidget);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(verifications, 0);
    await finish(tester);
  });
  for (final outcome in ['success', 'duplicate', 'failure', 'noop']) {
    testWidgets('seller verification $outcome has accurate feedback',
        (tester) async {
      duplicate = outcome == 'duplicate';
      failVerify = outcome == 'failure';
      noopVerify = outcome == 'noop';
      await mount(tester, const AdminDashboardPage());
      await tapAction(tester, 'seller_verify');
      await confirm(tester);
      expect(verifications, 1);
      expect(
          find.text(t(outcome == 'success'
              ? 'seller_verified_ok'
              : outcome == 'duplicate'
                  ? 'seller_already_verified'
                  : 'misc_seller_verify_failed')),
          findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      await finish(tester);
    });
  }
  for (final outcome in ['success', 'missing', 'failure']) {
    testWidgets('reported listing $outcome', (tester) async {
      available = outcome == 'success';
      failCar = outcome == 'failure';
      await mount(tester, const AdminDashboardPage());
      await tapAction(tester, 'ad_view');
      if (available) {
        expect(find.byType(CarDetailsPage), findsOneWidget);
        Navigator.of(tester.element(find.byType(CarDetailsPage))).pop();
        await frames(tester);
      } else {
        expect(
            find.text(t(failCar ? 'ui_report_listing_failed' : 'ad_not_found')),
            findsOneWidget);
      }
      expect(find.textContaining('private diagnostic'), findsNothing);
      await finish(tester);
    });
  }
  testWidgets('admin reviews user reports independently of ad reports',
      (tester) async {
    userReportRow = {
      'id': 'user-report-1',
      'reporter_id': 'reporter-1',
      'reported_user_id': 'reported-user-1',
      'offer_id': 'offer-1',
      'reason': 'harassment',
      'details': 'Repeated abusive messages',
      'status': 'open',
      'created_at': '2026-10-21T00:00:00Z',
    };
    await mount(tester, const AdminDashboardPage());
    await tester.drag(find.byType(ListView).last, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text(t('ugc_report_user_title')), findsOneWidget);
    expect(find.text('reported-user-1'), findsOneWidget);
    expect(find.text('Repeated abusive messages'), findsOneWidget);
    expect(find.text(t('ugc_report_reason_harassment')), findsOneWidget);

    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await frames(tester);
    final resolveUserReport = find.text(t('ad_status_reviewed')).last;
    await tester.tap(resolveUserReport);
    await frames(tester);
    expect(find.text(t('ugc_report_admin_confirm')), findsOneWidget);
    await tester.tap(find.text(t('ui_business_confirm')));
    await frames(tester);
    expect(
      requests.any(
        (uri) =>
            uri.path.endsWith('/user_reports') &&
            uri.queryParameters.containsKey('id'),
      ),
      isTrue,
    );
    expect(update?['status'], 'resolved');
    expect(userReportRow?['status'], 'resolved');
    await finish(tester);
  });
  testWidgets(
      'pending decision disables duplicate actions and survives disposal',
      (tester) async {
    gate = Completer<void>();
    await mount(tester, const AdminDashboardPage());
    await tapAction(tester, 'ad_status_reviewed');
    await confirm(tester);
    expect(patches, 1);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, t('ad_status_reviewed')))
            .onPressed,
        isNull);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  for (final stage in ['access', 'rows']) {
    testWidgets('reports late $stage cannot restore private rows',
        (tester) async {
      final pending = Completer<void>();
      if (stage == 'access') {
        accessGate = pending;
      } else {
        readGate = pending;
      }
      await mount(tester, const AdminDashboardPage());
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      pending.complete();
      await frames(tester);
      expect(find.text(t('admin_only_notice')), findsOneWidget);
      expect(find.text(row['reason']), findsNothing);
      if (stage == 'access') {
        expect(requests.where((u) => u.path.endsWith('/car_reports')), isEmpty);
      }
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  for (final seller in [false, true]) {
    testWidgets('reports confirmation seller=$seller rejects replaced session',
        (tester) async {
      await mount(tester, const AdminDashboardPage());
      await tapAction(tester, seller ? 'seller_verify' : 'ad_status_reviewed');
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      await tester.runAsync(() => supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only'));
      await frames(tester);
      await confirm(tester);
      expect(patches, 0);
      expect(verifications, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
    testWidgets('reports late write seller=$seller cannot announce success',
        (tester) async {
      gate = Completer<void>();
      await mount(tester, const AdminDashboardPage());
      await tapAction(tester, seller ? 'seller_verify' : 'ad_status_reviewed');
      await confirm(tester);
      expect(seller ? verifications : patches, 1);
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      final before = requests.length;
      gate!.complete();
      await frames(tester);
      expect(requests.length, before);
      expect(find.text(t('admin_only_notice')), findsOneWidget);
      expect(find.text(t(seller ? 'seller_verified_ok' : 'ui_report_updated')),
          findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('reports late listing read cannot navigate after logout',
      (tester) async {
    available = true;
    carGate = Completer<void>();
    await mount(tester, const AdminDashboardPage());
    await tapAction(tester, 'ad_view');
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
    carGate!.complete();
    await frames(tester);
    expect(find.byType(CarDetailsPage), findsNothing);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code} protected reported preview expires with session',
        (tester) async {
      available = true;
      appLocaleNotifier.value = locale;
      await mount(tester, const AdminDashboardPage(),
          dark: locale == AppLocale.ku);
      await tapAction(tester, 'ad_view');
      expect(find.byType(CarDetailsPage), findsOneWidget);
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      expect(find.byType(CarDetailsPage), findsNothing);
      expect(find.byKey(const ValueKey('account_scoped_view_expired')),
          findsOneWidget);
      await tester.runAsync(() => supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only'));
      await frames(tester);
      expect(find.byType(CarDetailsPage), findsNothing);
      expect(find.byKey(const ValueKey('account_scoped_view_expired')),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
}
