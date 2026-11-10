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
  var favoritesMode = 'populated';
  Completer<void>? favoriteReadGate;
  const newest = 'unused';
  final first = <String, dynamic>{
    'id': 'car-a',
    'user_id': 'seller-a',
    'brand': 'Toyota Land Cruiser',
    'model': 'Platinum with a long model name',
    'price': '٢٥٬٠٠٠',
    'year': 2024,
    'province': 'A long province name',
    'city': 'A long city name',
    'body_type': 'A long body type',
    'fuel': 'Hybrid',
    'transmission': 'Automatic',
    'mileage': '٤٥٬٠٠٠',
    'color': 'Pearl white',
    'images': <String>[]
  };
  final second = <String, dynamic>{
    'id': 'car-b',
    'user_id': 'seller-b',
    'brand': 'Kia',
    'model': 'Sportage with another long description',
    'price': 23000,
    'year': 2023,
    'mileage_km': 38000,
    'images': <String>[]
  };
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
          if (request.url.path.endsWith('/favorites')) {
            await favoriteReadGate?.future;
            if (favoritesMode == 'error') {
              return http.Response('{"message":"offline"}', 400,
                  headers: {'content-type': 'application/json'});
            }
            body = favoritesMode == 'empty'
                ? []
                : [
                    {'car_id': 'car-a', 'item_type': 'car'}
                  ];
          } else if (request.url.path.endsWith('/cars_public')) {
            body = [first];
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
    favoriteReadGate = null;
    compareCars.value = [];
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
      {bool dark = false, double width = 320, double scale = 1.6}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = Size(width, 640);
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
                            .copyWith(textScaler: TextScaler.linear(scale)),
                        child: child!))),
            home: page)));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await Scrollable.ensureVisible(tester.element(finder), alignment: .1);
    await tester.pumpAndSettle();
  }

  testWidgets('state gap favorites delayed loading', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    favoritesMode = 'empty';
    favoriteReadGate = Completer<void>();
    await mount(tester, const FavoritesPage());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(CarCard), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    await currentTypographyCheckpoint(tester, 'GAP_FAVORITES_LOADING');
    favoriteReadGate!.complete();
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final mode in ['populated', 'empty', 'error']) {
        testWidgets('$locale favorites $mode dark=$dark large text',
            (tester) async {
          favoritesMode = mode;
          appLocaleNotifier.value = locale;
          await mount(tester, const FavoritesPage(), dark: dark);
          if (mode == 'populated') {
            expect(find.byType(CarCard), findsOneWidget);
            await currentTypographyCheckpoint(tester, 'FAVORITES');
          } else {
            // Both empty and failed lists offer a recovery action.
            expect(find.byType(CarCard), findsNothing);
            final buttons = find.byType(FilledButton);
            expect(buttons, findsOneWidget);
            favoritesMode = 'populated';
            await tester.ensureVisible(buttons);
            await tester.pumpAndSettle();
            await tester.tap(buttons);
            await frames(tester);
            expect(find.byType(CarCard), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await finish(tester);
        });
      }
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final count in [0, 1, 2]) {
        testWidgets('$locale comparison $count cars dark=$dark large text',
            (tester) async {
          compareCars.value = [if (count > 0) first, if (count > 1) second];
          appLocaleNotifier.value = locale;
          await mount(tester, const CompareCarsPage(), dark: dark);
          if (count == 0) {
            expect(find.text(t('compare_add_hint')), findsOneWidget);
          } else {
            expect(find.byKey(const ValueKey('compare_car_0')), findsOneWidget);
            if (count == 1) {
              expect(find.text(t('compare_add_second')), findsOneWidget);
            }
            if (count == 2) {
              await currentTypographyCheckpoint(tester, 'COMPARE_HEADERS');
            }
            if (locale == AppLocale.en &&
                dark &&
                count == 2 &&
                const bool.fromEnvironment('UI_COMPARE_REVIEW_HOLD')) {
              debugPrint('UI_COMPARE_HEADERS_READY');
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(seconds: 20)));
            }
            await reveal(
                tester, find.byKey(const ValueKey('compare_spec_price')));
            expect(
                tester
                    .widget<SelectableText>(
                        find.byKey(const ValueKey('compare_price_0')))
                    .data,
                contains('USD'));
            if (count == 2) {
              await currentTypographyCheckpoint(tester, 'COMPARE_SPECS');
            }
            if (locale == AppLocale.en &&
                dark &&
                count == 2 &&
                const bool.fromEnvironment('UI_COMPARE_REVIEW_HOLD')) {
              debugPrint('UI_COMPARE_SPECS_READY');
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(seconds: 20)));
            }
            await reveal(
                tester, find.byKey(const ValueKey('compare_spec_color')));
          }
          expect(tester.takeException(), isNull);
          await finish(tester);
        });
      }
    }
  }
  testWidgets(
      'missing values and legacy mileage have readable currency and units',
      (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage());
    expect(
        tester
            .widget<SelectableText>(
                find.byKey(const ValueKey('compare_mileage_km_0')))
            .data,
        contains(t('unit_km_short')));
    expect(
        tester
            .widget<SelectableText>(
                find.byKey(const ValueKey('compare_color_1')))
            .data,
        t('common_unspecified'));
    expect(
        tester
            .widget<SelectableText>(
                find.byKey(const ValueKey('compare_price_0')))
            .data,
        contains('25,000\u00a0USD'));
    await finish(tester);
  });
  testWidgets(
      'remove one selection preserves the other and last removal shows empty',
      (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage());
    await reveal(tester, find.byKey(const ValueKey('compare_remove_0')));
    await tester.tap(find.byKey(const ValueKey('compare_remove_0')));
    await frames(tester);
    expect(compareCars.value.single['id'], 'car-b');
    expect(find.text(t('compare_add_second')), findsOneWidget);
    await reveal(tester, find.byKey(const ValueKey('compare_remove_0')));
    await tester.tap(find.byKey(const ValueKey('compare_remove_0')));
    await frames(tester);
    expect(find.text(t('compare_add_hint')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('clear comparison removes all selections', (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage());
    await reveal(tester, find.text(t('compare_clear')));
    await tester.tap(find.text(t('compare_clear')));
    await frames(tester);
    expect(compareCars.value, isEmpty);
    expect(find.text(t('compare_add_hint')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('wide normal text aligns both price values side by side',
      (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage(), width: 1024, scale: 1);
    await reveal(tester, find.byKey(const ValueKey('compare_spec_price')));
    final a = tester.getTopLeft(find.byKey(const ValueKey('compare_price_0'))),
        b = tester.getTopLeft(find.byKey(const ValueKey('compare_price_1')));
    expect((a.dy - b.dy).abs(), lessThan(1));
    expect((a.dx - b.dx).abs(), greaterThan(100));
    expect(tester.takeException(), isNull);
    await finish(tester);
  }, skip: const bool.fromEnvironment('NATIVE_VIEWPORT'));
  testWidgets('live locale keeps selections and translates spec labels',
      (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage());
    appLocaleNotifier.value = AppLocale.en;
    await frames(tester);
    expect(find.text(t('compare_title')), findsOneWidget);
    expect(find.text(t('field_mileage')), findsOneWidget);
    expect(compareCars.value.length, 2);
    await finish(tester);
  });
  testWidgets('selection rejects empty IDs and enforces two cars',
      (tester) async {
    late BuildContext selectedContext;
    await mount(tester, Builder(builder: (context) {
      selectedContext = context;
      return const Scaffold();
    }));
    toggleCompareCar({'id': '  '}, selectedContext);
    expect(compareCars.value, isEmpty);
    toggleCompareCar(first, selectedContext);
    toggleCompareCar(second, selectedContext);
    toggleCompareCar({'id': 'third'}, selectedContext);
    expect(compareCars.value.length, 2);
    await frames(tester);
    expect(find.text(t('compare_two_only')), findsOneWidget);
    toggleCompareCar({...first, 'id': ' car-a '}, selectedContext);
    expect(compareCars.value.single['id'], 'car-b');
    await finish(tester);
  });
  testWidgets(
      'view listing opens the selected car and keeps comparison on return',
      (tester) async {
    compareCars.value = [first, second];
    await mount(tester, const CompareCarsPage());
    final view = find.descendant(
        of: find.byKey(const ValueKey('compare_car_0')),
        matching: find.text(t('ad_view')));
    await reveal(tester, view);
    await tester.tap(view);
    await frames(tester);
    expect(find.byType(CarDetailsPage), findsOneWidget);
    expect(tester.widget<CarDetailsPage>(find.byType(CarDetailsPage)).car['id'],
        'car-a');
    Navigator.of(tester.element(find.byType(CarDetailsPage))).pop();
    await frames(tester);
    expect(compareCars.value.length, 2);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
