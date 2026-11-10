import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  var failCars = true, failMarket = true;
  Completer<void>? feedGate;
  final selected = ValueNotifier(false);
  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'plugins.flutter.io/google_mobile_ads/ump',
            (_) async => const StandardMethodCodec()
                .encodeErrorEnvelope(code: 'fixture_unavailable'));

    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((req) async {
          final primary = req.url.path.endsWith('/cars_public') &&
              req.url.queryParameters['limit'] == '20';
          final market = req.url.path.endsWith('/market_items');
          if (primary || market) await feedGate?.future;
          final failed = primary && failCars || market && failMarket;
          return http.Response(
              failed
                  ? jsonEncode(
                      {'message': 'private read diagnostics', 'code': 'XX000'})
                  : '[]',
              failed ? 500 : 200,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
  });
  setUp(() {
    failCars = failMarket = true;
    feedGate = null;
    selected.value = false;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  Future<void> mount(WidgetTester tester, {double scale = 1.6}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
            AppColors.isDark ? Brightness.dark : Brightness.light),
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Scaffold(
            body: SafeArea(child: HomeTab(marketSelected: selected)))));
    await frames(tester);
  }

  Future<void> reveal(WidgetTester tester, String key) async {
    await tester.scrollUntilVisible(find.byKey(ValueKey(key)), 220,
        scrollable: find.byType(Scrollable).first);
    await frames(tester);
  }

  Future<void> checkpoint(WidgetTester tester, String marker) async {
    if (!const bool.fromEnvironment('UI_REVIEW_HOLD')) return;
    debugPrint('REFERENCE_$marker');
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Home delayed feeds ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        failCars = failMarket = false;
        selected.value = true;
        feedGate = Completer<void>();
        await mount(tester);
        final loading = find.byKey(const ValueKey('home_cars_loading'));
        await tester.scrollUntilVisible(loading, 220,
            scrollable: find.byType(Scrollable).first);
        expect(loading, findsOneWidget);
        expect(tester.widget<Semantics>(loading).properties.liveRegion, isTrue);
        expect(tester.widget<Semantics>(loading).properties.label, t('ui_loading_title'));
        expect(find.text(t('car_no_ads')), findsNothing);
        expect(find.byKey(const ValueKey('home_cars_error')), findsNothing);
        await currentTypographyCheckpoint(tester, 'HOME_CARS_LOADING');
        final market = find.text(t('home_latest_market'));
        await tester.scrollUntilVisible(market, 250,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(t('market_no_ads')), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsWidgets);
        await currentTypographyCheckpoint(tester, 'HOME_MARKET_LOADING');
        feedGate!.complete();
        await frames(tester);
        expect(loading, findsNothing);
        expect(find.text(t('market_no_ads')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Home feed recovery ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester);
        await reveal(tester, 'home_cars_error');
        expect(find.text(t('car_no_ads')), findsNothing);
        await currentTypographyCheckpoint(tester, 'HOME_CARS_ERROR');
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await checkpoint(
              tester, 'HOME_ERROR_${locale.code.toUpperCase()}_CARS');
        }
        selected.value = true;
        await frames(tester);
        await reveal(tester, 'home_market_error');
        expect(find.text(t('market_no_ads')), findsNothing);
        await currentTypographyCheckpoint(tester, 'HOME_MARKET_ERROR');
        expect(find.textContaining('private read'), findsNothing);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await checkpoint(
              tester, 'HOME_ERROR_${locale.code.toUpperCase()}_MARKET');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'cars failure retries to real empty without false optional empty sections',
      (tester) async {
    failMarket = false;
    await mount(tester, scale: 1);
    await reveal(tester, 'home_cars_error');
    failCars = false;
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('home_cars_error')),
        matching: find.text(t('ui_retry'))));
    await frames(tester);
    expect(find.byKey(const ValueKey('home_cars_error')), findsNothing);
    expect(find.text(t('car_no_ads')), findsOneWidget);
    expect(find.text(t('home_most_requested')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'unselected market failure stays collapsed and selected retry recovers',
      (tester) async {
    failCars = false;
    await mount(tester, scale: 1);
    await frames(tester);
    expect(find.byKey(const ValueKey('home_market_error')), findsNothing);
    selected.value = true;
    await frames(tester);
    await reveal(tester, 'home_market_error');
    failMarket = false;
    await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('home_market_error')),
        matching: find.text(t('ui_retry'))));
    await frames(tester);
    expect(find.byKey(const ValueKey('home_market_error')), findsNothing);
    await tester.scrollUntilVisible(find.text(t('market_no_ads')), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.text(t('market_no_ads')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
