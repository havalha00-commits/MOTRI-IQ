import 'dart:convert';
import 'dart:async';
import 'package:flutter/services.dart';
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
  final car = <String, dynamic>{
    'id': 'car-a',
    'user_id': 'seller-a',
    'brand': 'Toyota',
    'model': 'Land Cruiser',
    'price': '١٥٠٬٠٠٠',
    'year': 2025,
    'province': 'Baghdad',
    'city': 'Baghdad',
    'images': <String>[]
  };
  final ad = BusinessAdData.fromJson({
    'id': 'business-a',
    'user_id': 'seller-b',
    'business_name': 'MOTRI automotive service',
    'category': 'Automotive services',
    'governorate': 'Erbil',
    'area': 'A long area name',
    'price': 100000,
    'package_id': 'private-package-id',
    'order_id': 'private-order-id',
    'status': 'active',
    'image_urls': <String>[]
  });
  const channel = MethodChannel('dev.fluttercommunity.plus/share');
  var shareFails = false, calls = 0;
  String result = 'selected-target';
  String? captured;
  Map<dynamic, dynamic>? arguments;
  Completer<void>? gate;
  final events = <Map<String, dynamic>>[];
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
          if (request.url.path.endsWith('/business_ad_events') &&
              request.method == 'POST') {
            events.add(Map<String, dynamic>.from(jsonDecode(request.body)));
          }
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
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() {
    requests.clear();
    captured = null;
    arguments = null;
    calls = 0;
    shareFails = false;
    result = 'selected-target';
    gate = null;
    events.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls++;
      arguments = call.arguments as Map;
      captured = arguments!['text'] as String?;
      await gate?.future;
      if (shareFails) throw PlatformException(code: 'private diagnostic');
      return result;
    });
    SharedPreferences.setMockInitialValues({
      'search_history': [newest, 'Older query', 'Older query', '']
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
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

  Widget page(bool business) =>
      business ? BusinessAdDetailsPage(ad: ad) : CarDetailsPage(car: car);
  Finder shareButton() => find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == t('ad_share'));
  Future<void> tapShare(WidgetTester tester) async {
    await tester.tap(shareButton());
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    test('${locale.code} car sharing uses USD field units at every magnitude',
        () {
      appLocaleNotifier.value = locale;
      for (final value in ['25000', '100000', '150000', '١٥٠٬٠٠٠', '۱۵۰٬۰۰۰']) {
        final message = buildCarShareText({...car, 'price': value});
        expect(message, contains(formatPriceDisplay(value)));
        expect(message, contains(t('share_location_label')));
      }
      expect(buildCarShareText(car), contains('196,500,000\u00a0IQD'));
    });
    test(
        '${locale.code} business sharing excludes advertising fees and order data',
        () {
      appLocaleNotifier.value = locale;
      final message = buildBusinessAdShareText(ad);
      expect(message, contains(ad.businessName));
      expect(message, contains(ad.locationText));
      expect(message, isNot(contains('100,000')));
      expect(message, isNot(contains('USD')));
      expect(message, isNot(contains('private-package-id')));
      expect(message, isNot(contains('private-order-id')));
    });
    for (final dark in [false, true]) {
      testWidgets('${locale.code} share text preview dark=$dark large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(
            tester,
            Scaffold(
                appBar: AppBar(title: Text(t('ad_share'))),
                body: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SelectableText(buildCarShareText(car)),
                          const Divider(height: 32),
                          SelectableText(buildBusinessAdShareText(ad)),
                        ]))),
            dark: dark);
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.en &&
            dark &&
            const bool.fromEnvironment('UI_SHARE_PREVIEW_REVIEW_HOLD')) {
          debugPrint('UI_SHARE_PREVIEW_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        await finish(tester);
      });
    }
    for (final business in [false, true]) {
      testWidgets(
          '${locale.code} business=$business share failure stays localized and retries',
          (tester) async {
        appLocaleNotifier.value = locale;
        shareFails = true;
        await mount(tester, page(business));
        await tapShare(tester);
        expect(find.text(t('ui_support_share_failed')), findsOneWidget);
        expect(find.textContaining('private diagnostic'), findsNothing);
        expect(events.where((e) => e['event_type'] == 'share'), isEmpty);
        shareFails = false;
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
            .hideCurrentSnackBar();
        await tester.pumpAndSettle();
        await tapShare(tester);
        expect(calls, 2);
        expect(captured,
            business ? buildBusinessAdShareText(ad) : buildCarShareText(car));
        expect(arguments!['originWidth'], greaterThan(0));
        expect(arguments!['originHeight'], greaterThan(0));
        if (business) {
          expect(events.where((e) => e['event_type'] == 'share').length, 1);
        }
        await finish(tester);
      });
    }
  }
  test('share labels remain readable and missing prices are omitted', () {
    expect(buildCarShareText({...car, 'price': 'Negotiable'}),
        contains('Negotiable'));
    expect(buildCarShareText({...car, 'price': 'Negotiable'}),
        isNot(contains('USD')));
    expect(buildCarShareText({...car, 'price': ''}),
        isNot(contains(t('share_price_label'))));
    expect(buildCarShareText({...car, 'price': '1e308'}),
        contains(t('compare_price_unknown')));
    expect(buildCarShareText(car).split('Baghdad').length - 1, 1);
  });
  for (final business in [false, true]) {
    testWidgets('business=$business share guard survives page disposal',
        (tester) async {
      gate = Completer<void>();
      await mount(tester, page(business));
      final action = tester.widget<IconButton>(shareButton()).onPressed!;
      action();
      await frames(tester);
      action();
      await frames(tester);
      expect(calls, 1);
      expect(tester.widget<IconButton>(shareButton()).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      gate!.complete();
      await frames(tester);
      expect(tester.takeException(), isNull);
    });
  }
  for (final dismissed in [false, true]) {
    testWidgets(
        'business share result dismissed=$dismissed counts only handoff',
        (tester) async {
      result = dismissed ? '' : 'dev.fluttercommunity.plus/share/unavailable';
      await mount(tester, page(true));
      await tapShare(tester);
      expect(events.where((e) => e['event_type'] == 'share').length,
          dismissed ? 0 : 1);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
}
