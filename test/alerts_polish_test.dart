import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:async';
import 'package:motri_iq/ui/activity_notification_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motri_iq/backend_api.dart';
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
      failPatch = false,
      failCar = false,
      empty = false,
      available = false,
      noopPatch = false;
  var patches = 0;
  Completer<void>? gate;
  late BackendApi previousBackendApi;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    previousBackendApi = backendApi;
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
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      client: MockClient((request) async {
        requests.add(request.url);
        Object body;
        var statusCode = 200;
        if (request.url.path == '/api/activity/car-alerts') {
          if (failRead) {
            body = {'error': 'private diagnostic'};
            statusCode = 500;
          } else {
            body = {
              'success': true,
              'data': empty
                  ? <dynamic>[]
                  : [
                      {
                        'id': 'alert-1',
                        'car_id': 'car-1',
                        'brand': 'Toyota Land Cruiser',
                        'model': 'Platinum with a long model description',
                        'province': 'A long province name',
                        'city': 'A long city name',
                        'price': 25000
                      }
                    ]
            };
          }
        } else if (request.url.path ==
            '/api/activity/car-alerts/alert-1/read') {
          patches++;
          await gate?.future;
          if (failPatch) {
            body = {'error': 'private diagnostic'};
            statusCode = 500;
          } else {
            body = {
              'success': true,
              'data': noopPatch ? null : {'id': 'alert-1'}
            };
          }
        } else if (request.url.path == '/api/cars/by-ids') {
          if (failCar) {
            body = {'error': 'private diagnostic'};
            statusCode = 500;
          } else {
            body = {
              'success': true,
              'data': available
                  ? [
                      {
                        'id': 'car-1',
                        'user_id': 'seller-1',
                        'brand': 'Toyota',
                        'model': 'Camry',
                        'price': 25000,
                        'year': 2024,
                        'images': <String>[],
                        'created_at': '2026-10-21T00:00:00Z'
                      }
                    ]
                  : <dynamic>[]
            };
          }
        } else {
          body = {'error': 'Unexpected test request'};
          statusCode = 500;
        }
        return http.Response(
          jsonEncode(body),
          statusCode,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() {
    requests.clear();
    failRead = failPatch = failCar = empty = available = noopPatch = false;
    patches = 0;
    gate = null;
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
    backendApi = previousBackendApi;
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
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

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('$locale alerts dark=$dark large text', (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, const AlertsPage(), dark: dark);
        expect(find.byType(ActivityNotificationTile), findsOneWidget);
        expect(find.text(t('ui_notification_unread')), findsOneWidget);
        expect(find.textContaining('USD'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'ALERTS');
        if (locale == AppLocale.en &&
            dark &&
            const bool.fromEnvironment('UI_ALERTS_REVIEW_HOLD')) {
          debugPrint('UI_ALERTS_POLISH_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        await finish(tester);
      });
    }
  }
  testWidgets('failed read retries and empty can refresh', (tester) async {
    failRead = true;
    await mount(tester, const AlertsPage());
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    failRead = false;
    empty = true;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('alerts_empty')), findsOneWidget);
    empty = false;
    await tester.tap(find.byTooltip(t('alerts_update')));
    await frames(tester);
    expect(find.byType(ActivityNotificationTile), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'unavailable listing has localized feedback and scoped read update',
      (tester) async {
    await mount(tester, const AlertsPage());
    await tester.tap(find.byType(ActivityNotificationTile));
    await frames(tester);
    expect(find.text(t('ad_unavailable')), findsOneWidget);
    final patch = requests.firstWhere(
        (uri) => uri.path.endsWith('/api/activity/car-alerts/alert-1/read'));
    expect(patch.queryParameters, isEmpty);
    expect(patches, 1);
    await finish(tester);
  });
  testWidgets('listing read failure preserves unread and allows retry',
      (tester) async {
    failCar = true;
    await mount(tester, const AlertsPage());
    await tester.tap(find.byType(ActivityNotificationTile));
    await frames(tester);
    expect(patches, 0);
    expect(find.text(t('alerts_open_failed')), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    failCar = false;
    await tester.tap(find.byType(ActivityNotificationTile));
    await frames(tester);
    expect(patches, 1);
    await finish(tester);
  });
  for (final noop in [false, true]) {
    testWidgets('read update failure/noop=$noop still opens listing',
        (tester) async {
      available = true;
      failPatch = !noop;
      noopPatch = noop;
      await mount(tester, const AlertsPage());
      await tester.tap(find.byType(ActivityNotificationTile));
      await frames(tester);
      expect(find.byType(CarDetailsPage), findsOneWidget);
      Navigator.of(tester.element(find.byType(CarDetailsPage))).pop();
      await frames(tester);
      expect(find.text(t('ui_alert_read_failed')), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      await finish(tester);
    });
  }
  testWidgets('duplicate opens are guarded and disposal is safe',
      (tester) async {
    gate = Completer<void>();
    await mount(tester, const AlertsPage());
    await tester.tap(find.byType(ActivityNotificationTile));
    await frames(tester);
    await tester.tap(find.byType(ActivityNotificationTile));
    await frames(tester);
    expect(patches, 1);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
}
