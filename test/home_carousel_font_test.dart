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
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  const photo =
      'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET',
              reason: 'Home carousel is a read-only review');
          final rows = request.url.path.endsWith('/cars_public')
              ? List.generate(
                  3,
                  (i) => {
                        'id': 'carousel-$i',
                        'brand': 'MOTRI',
                        'model': [
                          'Family SUV',
                          'City sedan',
                          'Touring edition'
                        ][i],
                        'year': 2025,
                        'price': 25000 + i * 1000,
                        'city': 'Baghdad',
                        'image_url': jsonEncode([photo])
                      })
              : [];
          return http.Response(jsonEncode(rows), 200,
              request: request, headers: {'content-type': 'application/json'});
        }));
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('carousel ${locale.code} dark=$dark scale=$scale',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize = const Size(360, 760);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(body: SafeArea(child: HomeTab())),
          ));
          await frames(tester);
          final carousel = find.byKey(const ValueKey('home_featured_carousel'));
          expect(carousel, findsOneWidget);
          await Scrollable.ensureVisible(tester.element(carousel),
              alignment: .15);
          await frames(tester);
          if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            Object? imageError;
            await tester.runAsync(() => precacheImage(
                    NetworkImage(photo), tester.element(carousel),
                    onError: (error, stack) => imageError = error)
                .timeout(const Duration(seconds: 25)));
            expect(imageError, isNull,
                reason: 'Carousel review requires loaded listing photos');
            await frames(tester);
          }
          final pager = tester.widget<PageView>(
              find.descendant(of: carousel, matching: find.byType(PageView)));
          expect(pager.controller!.page, 0);
          await tester.tap(find.byTooltip(t('ui_carousel_next')));
          await frames(tester);
          expect(pager.controller!.page, 1);
          await tester.tap(find.byTooltip(t('ui_carousel_previous')));
          await frames(tester);
          expect(pager.controller!.page, 0);
          final theme = Theme.of(tester.element(carousel));
          expect(theme.textTheme.bodyMedium!.fontFamily, 'MotriLatin');
          expect(theme.textButtonTheme.style!.textStyle!.resolve({})!.fontFamily,
              'MotriLatin');
          expect(theme.textTheme.bodyMedium!.fontFamilyFallback,
              contains(locale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans'));
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('UI_FONT_CAROUSEL_HOLD') &&
              scale == 1) {
            // ignore: avoid_print
            print(
                'FONT_CAROUSEL_${locale.code.toUpperCase()}_${dark ? 'DARK' : 'LIGHT'}');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 10)));
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        });
      }
    }
  }
}
