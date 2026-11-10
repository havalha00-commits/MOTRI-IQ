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
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> checkpoint(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('UI_REVIEW_HOLD')) return;
  debugPrint('REFERENCE_$name');
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final rows = jsonDecode(
          r'''[{"brand": "Chery", "model": "Arrizo 5", "price": 20000.0, "year": 2025, "city": "بغداد", "province": "بغداد", "mileage_km": null, "images": ["https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg"], "id": "visual-car-0", "status": "active", "created_at": "2026-10-20T10:00:00Z"}, {"brand": "Jetour", "model": "X70 Plus", "price": 27000.0, "year": 2026, "city": "بغداد", "province": "بغداد", "mileage_km": null, "images": ["https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/jetour_x70_plus.jpg"], "id": "visual-car-1", "status": "active", "created_at": "2026-10-20T10:00:00Z"}, {"brand": "GAC", "model": "GS8", "price": 45000.0, "year": 2026, "city": "بغداد", "province": "بغداد", "mileage_km": null, "images": ["https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/gac_gs8.jpg"], "id": "visual-car-2", "status": "active", "created_at": "2026-10-20T10:00:00Z"}]''')
      as List;
  for (final row in rows) {
    row['image_url'] = jsonEncode(row['images']);
  }
  setUpAll(() async {
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async => http.Response(
            jsonEncode(request.url.path.endsWith('/cars_public')
                ? (request.url.query.toLowerCase().contains('chery')
                    ? [rows.first]
                    : rows)
                : []),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'})));
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Reference discovery ${locale.code} dark=$dark',
          (tester) async {
        appLocaleNotifier.value = locale;
        app.AppColors.isDark = dark;
        await tester.pumpWidget(MaterialApp(
            key: UniqueKey(),
            debugShowCheckedModeBanner: false,
            theme: app.buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            home: AuthCapabilitiesScope(
                loader: () async => const AuthCapabilitiesResult.ready(
                    AuthCapabilities(
                        phoneOtpEnabled: true, emailEnabled: true)),
                child: const app.HomePage())));
        await frames(tester);
        for (var i = 0;
            i < 100 && find.byType(app.CarCard).evaluate().isEmpty;
            i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byType(app.CarCard), findsWidgets);
        Object? imageError;
        await tester.runAsync(() => precacheImage(
              NetworkImage((rows.first['images'] as List).first as String),
              tester.element(find.byType(app.HomePage)),
              onError: (error, stack) {
                imageError = error;
              },
            ).timeout(const Duration(seconds: 25)));
        await frames(tester);
        expect(imageError, isNull,
            reason: 'Loaded vehicle photography is required for visual review');
        // Useful inventory appears in the opening viewport, ahead of secondary feeds.
        expect(tester.getTopLeft(find.byType(app.CarCard).first).dy,
            lessThan(450));
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.ar && !dark) {
          await checkpoint(tester, 'HOME_AR');
        }
        if (locale == AppLocale.ku && dark) {
          await checkpoint(tester, 'HOME_KU_DARK');
        }
        await tester.tap(find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(t('nav_search'))));
        await frames(tester);
        expect(find.byType(TextField), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Chery');
        await frames(tester);
        await tester.tap(find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == t('search')));
        await frames(tester);
        expect(find.byType(app.CarCard), findsWidgets);
        expect(tester.getTopLeft(find.byType(app.CarCard).first).dy,
            lessThan(450));
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.ar && !dark) {
          await checkpoint(tester, 'SEARCH_AR');
        }
        if (locale == AppLocale.ku && dark) {
          await checkpoint(tester, 'SEARCH_KU_DARK');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
