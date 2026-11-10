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

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  var viewEvents = 0;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path.endsWith('/increment_ad_counter') ||
              path.endsWith('/business_ad_events')) {
            expectSync(request.method, 'POST');
            if (path.endsWith('/business_ad_events')) viewEvents++;
            // Local analytics only; no request reaches a real service.
            return http.Response('null', 200,
                request: request,
                headers: {'content-type': 'application/json'});
          }
          expectSync(request.method, 'GET',
              reason: 'Detail review must not submit listings/offers');
          return http.Response(jsonEncode([]), 200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
    viewEvents = 0;
  });
  Widget host(Widget page, AppLocale locale, bool dark) => MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(const int.fromEnvironment('DETAIL_TEXT_PERCENT', defaultValue: 160) / 100)),
            child: child!),
        home: page,
      );
  test('business location omits empty and duplicate places', () {
    expect(
        BusinessAdData.fromJson({'governorate': ' Baghdad ', 'area': 'Baghdad'})
            .locationText,
        'Baghdad');
    expect(
        BusinessAdData.fromJson({'governorate': ' ', 'area': 'Mansour'})
            .locationText,
        'Mansour');
    expect(
        BusinessAdData.fromJson({'governorate': 'Baghdad', 'area': 'Mansour'})
            .locationText,
        'Baghdad · Mansour');
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final sold in [false, true]) {
        testWidgets('${locale.code} car details sold=$sold dark=$dark',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize = Size(
                const int.fromEnvironment('DETAIL_WIDTH', defaultValue: 320).toDouble(),
                720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
          }
          await tester.pumpWidget(host(
              CarDetailsPage(car: {
                'id': 'fixture-car',
                'brand': 'MOTRI',
                'model': 'Long model name for a family vehicle',
                'year': 2025,
                'price': 25000,
                'status': sold ? 'sold' : 'active',
                'city': 'Baghdad',
                'province': 'Baghdad',
                'mileage_km': 12500,
                'fuel': 'Petrol',
                'transmission': 'Automatic',
                'body_type': 'Sport utility vehicle with seven seats',
                'color': 'Pearl white',
                'seller_phone': '07715339922',
                'description': 'A carefully maintained family vehicle.',
                'created_at': '2026-10-21',
              }),
              locale,
              dark));
          await frames(tester);
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(
              find.byKey(const ValueKey('vehicle_primary_price')), 160,
              scrollable: find.byType(Scrollable).first);
          await frames(tester);
          final primary = tester.widget<Text>(
              find.byKey(const ValueKey('vehicle_primary_price')));
          await tester.scrollUntilVisible(
              find.byKey(const ValueKey('vehicle_secondary_price')), 100,
              scrollable: find.byType(Scrollable).first);
          await frames(tester);
          final secondary = tester.widget<Text>(
              find.byKey(const ValueKey('vehicle_secondary_price')));
          expect(
              primary.data!.replaceAll('\u00a0', ' '), contains('25,000 USD'));
          expect(secondary.data, contains('IQD'));
          expect(primary.textDirection, TextDirection.ltr);
          final luminance = primary.style!.color!.computeLuminance();
          final background = AppColors.scaffold.computeLuminance();
          final contrast = luminance > background
              ? (luminance + .05) / (background + .05)
              : (background + .05) / (luminance + .05);
          expect(contrast, greaterThanOrEqualTo(4.5),
              reason: 'Asking price must remain readable in both themes');
          if (!sold) {
            final action = find.byKey(const ValueKey('vehicle_offer_action'));
            final button = tester.widget<FilledButton>(action);
            final scheme = Theme.of(tester.element(action)).colorScheme;
            expect(button.style!.backgroundColor!.resolve({}), scheme.primary);
            expect(button.style!.foregroundColor!.resolve({}), scheme.onPrimary);
            await Scrollable.ensureVisible(tester.element(action), alignment: 1);
            await frames(tester);
            final gap = tester.getTopLeft(action).dy - tester.getBottomLeft(
                find.byKey(const ValueKey('vehicle_market_estimate'))).dy;
            expect(gap, greaterThanOrEqualTo(16));
          }
          if (!sold) {
            await Scrollable.ensureVisible(
                tester.element(
                    find.byKey(const ValueKey('vehicle_primary_price'))),
                alignment: .35);
            await frames(tester);
            await currentTypographyCheckpoint(tester, 'CAR_DETAIL');
          }
          final fuelTile =
              find.byKey(ValueKey('vehicle_spec:${t('field_fuel')}'));
          await tester.scrollUntilVisible(fuelTile, 180,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(fuelTile);
          await frames(tester);
          expect(find.descendant(of: fuelTile, matching: find.text('Petrol')),
              findsOneWidget);
          final fuelValue = tester.widget<Text>(
              find.descendant(of: fuelTile, matching: find.text('Petrol')));
          expect(fuelValue.textDirection, TextDirection.ltr);
          if (const int.fromEnvironment('DETAIL_TEXT_PERCENT', defaultValue: 160) == 100 &&
              tester.view.physicalSize.width / tester.view.devicePixelRatio >= 360 &&
              tester.view.physicalSize.width / tester.view.devicePixelRatio < 560) {
            final bodyTile = find.byKey(ValueKey('vehicle_spec:${t('field_body_type')}'));
            final colorTile = find.byKey(ValueKey('vehicle_spec:${t('field_color')}'));
            expect(tester.getSize(bodyTile).height, tester.getSize(colorTile).height,
                reason: 'A wrapped value and its adjacent short value share row height');
          }
          final specIcon = tester.widget<Icon>(
              find.descendant(of: fuelTile, matching: find.byType(Icon)));
          final iconLuminance = specIcon.color!.computeLuminance();
          final iconContrast = iconLuminance > background
              ? (iconLuminance + .05) / (background + .05)
              : (background + .05) / (iconLuminance + .05);
          expect(iconContrast, greaterThanOrEqualTo(3),
              reason: 'Specification icons stay visible in both themes');
          if (!sold) await currentTypographyCheckpoint(tester, 'DETAIL_SPECS');
          for (var i = 0; i < 7; i++) {
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -350));
            await frames(tester);
            expect(tester.takeException(), isNull);
          }
          expect(find.text(t('settings_call')), findsOneWidget);
          expect(find.text(t('contact_whatsapp')), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        });
      }
      testWidgets('${locale.code} business details dark=$dark', (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.physicalSize = Size(
                const int.fromEnvironment('DETAIL_WIDTH', defaultValue: 320).toDouble(),
                720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        await tester.pumpWidget(host(
            BusinessAdDetailsPage(
                ad: BusinessAdData.fromJson({
              'id': 'fixture-business',
              'business_name':
                  'MOTRI automotive service and accessories centre',
              'category': 'Automotive services',
              'description':
                  'Professional service and accessories for your car.',
              'phone': '07715339922',
              'whatsapp': '07715339922',
              'governorate': 'Baghdad',
              'area': 'Baghdad',
              'address': 'A long address with directions to the showroom',
              'working_hours': '09:00 – 18:00',
            })),
            locale,
            dark));
        await frames(tester);
        expect(tester.takeException(), isNull);
        expect(
            tester
                .widget<SliverAppBar>(find.byType(SliverAppBar))
                .flexibleSpace,
            isNull,
            reason: 'No empty hero can overlap the toolbar');
        expect(viewEvents, 1,
            reason: 'A no-photo business still records exactly one local view');
        expect(find.byTooltip(t('ad_share')), findsOneWidget);
        if (const bool.fromEnvironment('UI_DETAIL_REVIEW_HOLD') &&
            locale == AppLocale.en &&
            dark) {
          debugPrint('UI_DETAIL_REVIEW_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 15)));
        }
        for (var i = 0; i < 6; i++) {
          await tester.drag(
              find.byType(CustomScrollView), const Offset(0, -350));
          await frames(tester);
          expect(tester.takeException(), isNull);
        }
        expect(find.byTooltip(t('ad_share')), findsOneWidget,
            reason: 'Share remains available after view recording');
        expect(viewEvents, 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester);
      });
    }
  }
}
