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
import 'package:motri_iq/ui/form_section.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  var includePackages = false;
  var failPackages = false;
  Future<void> signIn() => Supabase.instance.client.auth
      .signInWithPassword(email: 'fixture@example.com', password: 'local-only')
      .then((_) {});
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    const userId = '00000000-0000-4000-8000-000000000001';
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
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async {
          if (!request.url.path.startsWith('/auth/v1/')) {
            expectSync(request.method, 'GET',
                reason: 'Form fixtures reject submissions');
          }
          if (request.url.path.endsWith('/business_ad_packages') &&
              failPackages) {
            return http.Response('{"message":"fixture package failure"}', 400,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          Object body = [];
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
              'refresh_token': 'local-fixture',
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
          } else if (request.url.path.endsWith('/business_ad_packages') &&
              includePackages) {
            body = [
              for (final name in ['Standard', 'Premium'])
                {
                  'id': name.toLowerCase(),
                  'name': name,
                  'duration_days': 7,
                  'price': 10,
                  'placements': ['home'],
                  'features': ['Featured'],
                  'is_active': true,
                }
            ];
          } else if (request.url.path == '/auth/v1/logout') {
            body = {};
          } else {
            expectSync(request.method, 'GET',
                reason: 'Form layout tests must not upload or submit');
          }
          return http.Response(jsonEncode(body), 200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    await signIn();
  });
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  tearDown(() {
    includePackages = false;
    failPackages = false;
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });

  Widget host(Widget page, AppLocale locale, bool dark, {double scale = 1.4}) =>
      MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: Directionality(textDirection: locale.direction, child: page),
      );

  test('Arabic and Persian form numbers retain their values', () {
    expect(parseFormInteger('٢٠٢٦'), 2026);
    expect(parseFormInteger('۲۰۲۶'), 2026);
    expect(parseFormDecimal('٥٠٬٠٠٠٫٥'), 50000.5);
    expect(parseFormDecimal('50,000.5'), 50000.5);
    expect(parseFormDecimal('NaN'), isNull);
    expect(parseFormDecimal('Infinity'), isNull);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final entry in <String, Widget>{
        'vehicle': const AddCarTab(),
        'showroom': const ManageShowroomPage(),
        'business': const CreateBusinessAdPage(),
      }.entries) {
        testWidgets('${locale.code} ${entry.key} form, dark=$dark',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize = const Size(320, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          await tester.pumpWidget(host(entry.value, locale, dark));
          await frames(tester);
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('UI_FORM_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark) {
            debugPrint('UI_FORM_${entry.key.toUpperCase()}_REVIEW_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          final list = find.byType(Scrollable).first;
          await tester.drag(list, const Offset(0, -260));
          await frames(tester);
          expect(tester.takeException(), isNull);
          for (final field
              in tester.widgetList<TextField>(find.byType(TextField))) {
            if (field.keyboardType == TextInputType.phone) {
              expect(field.textDirection, TextDirection.ltr);
            }
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      }
    }
    testWidgets(
        '${locale.code}: inline year and price validation accepts localized digits',
        (tester) async {
      appLocaleNotifier.value = locale;
      await tester.pumpWidget(host(const AddCarTab(), locale, false, scale: 1));
      await frames(tester);
      final year = find.byKey(const ValueKey('car_year'));
      final scroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(year, 180, scrollable: scroll);
      await tester.enterText(year, 'not a year');
      await frames(tester);
      expect(
          find.text(t('ui_invalid_year')
              .replaceAll('{year}', '${DateTime.now().year + 1}')),
          findsOneWidget);
      await tester.enterText(year, '٢٠٢٦');
      await frames(tester);
      expect(tester.state<FormFieldState<String>>(year).validate(), isTrue);
      final price = find.byKey(const ValueKey('car_price'));
      await tester.scrollUntilVisible(price, 100, scrollable: scroll);
      await tester.enterText(price, '-3');
      await frames(tester);
      expect(find.text(t('ui_invalid_price')), findsOneWidget);
      await tester.enterText(price, '٥٠٬٠٠٠٫٥');
      await frames(tester);
      expect(tester.state<FormFieldState<String>>(price).validate(), isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  testWidgets('signed-out showroom has a useful locked state', (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester
        .pumpWidget(host(const ManageShowroomPage(), AppLocale.ar, false));
    await frames(tester);
    expect(find.text(t('login_required_first')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(signIn);
  });
  testWidgets(
      'business packages form one group and retain the selected package',
      (tester) async {
    appLocaleNotifier.value = AppLocale.en;
    includePackages = true;
    await tester.pumpWidget(
        host(const CreateBusinessAdPage(), AppLocale.en, false, scale: 1));
    await frames(tester);
    final group = find.byType(RadioGroup<String>);
    await tester.scrollUntilVisible(group, 240,
        scrollable: find.byType(Scrollable).first);
    await frames(tester);
    expect(group, findsOneWidget);
    final option = find.byType(RadioListTile<String>).last;
    await tester.ensureVisible(option);
    await tester.tap(option);
    await frames(tester);
    expect(tester.widget<RadioGroup<String>>(group).groupValue, 'premium');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('package retry preserves the business draft', (tester) async {
    appLocaleNotifier.value = AppLocale.en;
    failPackages = true;
    await tester.pumpWidget(
        host(const CreateBusinessAdPage(), AppLocale.en, false, scale: 1));
    await frames(tester);
    final name = find.byKey(const ValueKey('business_name'));
    await tester.enterText(name, 'Draft garage');
    await tester.scrollUntilVisible(find.text(t('ui_retry')), 240,
        scrollable: find.byType(Scrollable).first);
    await frames(tester);
    await tester.ensureVisible(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('ui_retry')).hitTestable(), findsOneWidget);
    failPackages = false;
    includePackages = true;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    await tester.scrollUntilVisible(find.byType(RadioGroup<String>), 120,
        scrollable: find.byType(Scrollable).first);
    expect(find.byType(RadioGroup<String>), findsOneWidget);
    await tester.scrollUntilVisible(name, -240,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<TextFormField>(name).controller!.text, 'Draft garage');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('offer dialog validates and closes safely above keyboard',
      (tester) async {
    appLocaleNotifier.value = AppLocale.en;
    await tester.pumpWidget(host(
        CarDetailsPage(car: {
          'id': 'fixture-car',
          'brand': 'MOTRI',
          'model': 'Family car',
          'price': 25000,
          'seller_id': '00000000-0000-4000-8000-000000000002',
        }),
        AppLocale.en,
        false,
        scale: 1.4));
    await frames(tester);
    final offer = find.text(t('offer_price_cta'));
    await tester.scrollUntilVisible(offer, 240,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await frames(tester);
    final amount = find.byKey(const ValueKey('offer_amount'));
    await tester.enterText(amount, '-١');
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(find.text(t('req_price_positive')), findsOneWidget);
    expect(find.text('Asking price: 25000 USD'), findsOneWidget);
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(t('common_cancel')));
    await tester.pumpAndSettle();
    expect(find.text(t('offer_your_price')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
