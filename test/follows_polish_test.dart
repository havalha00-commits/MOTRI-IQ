import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
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
  var failFollows = false, failProfiles = false, empty = false;
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
          if (request.url.path.endsWith('/user_follows')) {
            if (failFollows) {
              return http.Response('{"message":"private diagnostic"}', 500);
            }
            body = empty
                ? []
                : [
                    {
                      'followed_id': 'seller-1',
                      'created_at': '2026-10-20T12:00:00Z'
                    },
                    {'followed_id': 'seller-2', 'created_at': 'invalid'}
                  ];
          }
          if (request.url.path.endsWith('/profiles')) {
            if (failProfiles) {
              return http.Response('{}', 500);
            }
            body = [
              {
                'id': 'seller-1',
                'full_name':
                    'A long seller showroom name for wrapping and alignment'
              }
            ];
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() {
    requests.clear();
    failFollows = failProfiles = empty = false;
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

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('$locale following dark=$dark large text', (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, const MyFollowsPage(), dark: dark);
        expect(
            find.text('A long seller showroom name for wrapping and alignment'),
            findsOneWidget);
        await tester.scrollUntilVisible(
            find.text(t('default_seller_name')), 150);
        expect(find.text(t('default_seller_name')), findsOneWidget);
        await tester.drag(find.byType(ListView), const Offset(0, 600));
        await tester.pumpAndSettle();
        expect(find.textContaining('2026-10-20T'), findsNothing);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'FOLLOWS');
        if (locale == AppLocale.en &&
            dark &&
            const bool.fromEnvironment('UI_FOLLOWS_REVIEW_HOLD')) {
          debugPrint('UI_FOLLOWS_POLISH_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 45)));
        }
        await finish(tester);
      });
    }
  }
  testWidgets(
      'profile failure retains every seller and navigation uses saved ID',
      (tester) async {
    failProfiles = true;
    await mount(tester, const MyFollowsPage());
    expect(find.text(t('default_seller_name')), findsNWidgets(2));
    await tester.tap(find.text(t('default_seller_name')).first);
    await frames(tester);
    expect(find.byType(SellerProfilePage), findsOneWidget);
    expect(
        tester
            .widget<SellerProfilePage>(find.byType(SellerProfilePage))
            .sellerId,
        'seller-1');
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('failed follow read retries without exposing diagnostics',
      (tester) async {
    failFollows = true;
    await mount(tester, const MyFollowsPage());
    expect(find.textContaining('private diagnostic'), findsNothing);
    failFollows = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text('A long seller showroom name for wrapping and alignment'),
        findsOneWidget);
    await finish(tester);
  });
  testWidgets('empty following remains refreshable', (tester) async {
    empty = true;
    await mount(tester, const MyFollowsPage());
    expect(find.text(t('account_not_following')), findsOneWidget);
    empty = false;
    tester.state<RefreshIndicatorState>(find.byType(RefreshIndicator)).show();
    await tester.pumpAndSettle();
    await frames(tester);
    expect(find.text('A long seller showroom name for wrapping and alignment'),
        findsOneWidget);
    await finish(tester);
  });
}
