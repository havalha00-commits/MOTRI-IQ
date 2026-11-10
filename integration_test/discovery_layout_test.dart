import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart' as app;
import 'package:motri_iq/auth/auth_capabilities.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native discovery layouts with controlled public listing fixtures',
      (tester) async {
    final cars = List.generate(
        20,
        (i) => {
              'id': 'fixture-car-$i',
              'brand': 'Toyota',
              'model': 'Land Cruiser Platinum',
              'year': 2025,
              'price': 73000,
              'city': 'بغداد',
              'province': 'بغداد',
              'mileage_km': 123456,
              'status': i == 0 ? 'sold' : 'active',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async {
          return http.Response(
              jsonEncode(request.url.path.endsWith('/cars_public') ? cars : []),
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        debugPrint('Native fixture review: ${locale.code}, dark=$dark');
        appLocaleNotifier.value = locale;
        app.AppColors.isDark = dark;
        await tester.pumpWidget(MaterialApp(
          key: UniqueKey(),
          theme: app.buildAppTheme(dark ? Brightness.dark : Brightness.light),
          locale: locale.locale,
          supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
          localizationsDelegates: appLocalizationsDelegates,
          home: AuthCapabilitiesScope(
              loader: () async => const AuthCapabilitiesResult.ready(
                  AuthCapabilities(phoneOtpEnabled: true, emailEnabled: true)),
              child: const app.HomePage()),
        ));
        await frames(tester);
        expect(tester.takeException(), isNull);
        for (var i = 0;
            i < 100 && find.byType(app.CarCard).evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(app.CarCard), findsWidgets);
        final homeList = find
            .descendant(
                of: find.byType(app.HomeTab), matching: find.byType(ListView))
            .first;
        await tester.drag(homeList, const Offset(0, -180));
        await frames(tester);
        expect(find.byType(app.CarCard), findsWidgets);
        expect(find.text('بغداد'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(t('nav_cars'))));
        await frames(tester);
        expect(find.byType(app.SectionPage), findsOneWidget);
        expect(find.byType(app.CarCard), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    }
  });
}
