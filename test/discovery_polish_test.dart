import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/ui/carousel_position.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async => http.Response('[]', 200,
            request: request, headers: {'content-type': 'application/json'})));
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });

  testWidgets('long carousel remains bounded and exposes the current position',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: Center(
      child: SizedBox(
          width: 160,
          child: CarouselPosition(
              count: 50,
              active: 49,
              color: Colors.red,
              inactiveColor: Colors.grey)),
    ))));
    expect(tester.takeException(), isNull);
    expect(find.text('50 / 50'), findsOneWidget);
    expect(tester.getSemantics(find.byType(CarouselPosition)).value, '50 / 50');
    semantics.dispose();
  });

  testWidgets('carousel autoplay respects reduced motion', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: const Scaffold(
          body: CarMarqueeStrip(cars: [
        {'id': 'first', 'brand': 'Toyota', 'model': 'Camry'},
        {'id': 'second', 'brand': 'Kia', 'model': 'Sportage'},
      ])),
    )));
    await tester.pump(const Duration(seconds: 5));
    expect(tester.widget<PageView>(find.byType(PageView)).controller!.page, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('${locale.code} listing card, dark=$dark scale=$scale',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            home: Directionality(
                textDirection: locale.direction,
                child: Scaffold(
                    body: Center(
                  child: SizedBox(
                      width: 140,
                      height: 230,
                      child: CarCard(square: true, car: const {
                        'id': 'layout-car',
                        'brand': 'Toyota',
                        'model': 'Land Cruiser Platinum',
                        'year': 2025,
                        'mileage_km': 123456,
                        'price': 73000,
                        'original_price': 75000,
                        'price_drop': 2000,
                        'city': 'بغداد',
                        'province': 'بغداد',
                        'status': 'sold',
                      })),
                ))),
          ));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 200));
          expect(tester.takeException(), isNull);
          expect(find.text('بغداد'), findsOneWidget,
              reason: 'Duplicate city/province should not crowd the card');
          expect(
              find.text('2025 • 123456 ${t('unit_km_short')}'), findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
