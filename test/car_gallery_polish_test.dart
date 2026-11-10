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
import 'package:motri_iq/ui/photo_gallery.dart';
import 'support/current_typography_checkpoint.dart';

const native = bool.fromEnvironment('NATIVE_VIEWPORT');
const photo =
    'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg';
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async => http.Response(
            request.method == 'GET' ? '[]' : 'null', 200,
            request: request, headers: {'content-type': 'application/json'})));
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('decoded car gallery ${locale.code} dark=$dark',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
          locale: locale.locale,
          supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
          localizationsDelegates: appLocalizationsDelegates,
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!),
          // Repeat a known public photo to isolate paging/zoom from listing data.
          home: CarDetailsPage(car: {
            'id': 'gallery-fixture',
            'brand': 'Chery',
            'model': 'Arrizo 5',
            'price': 12000,
            'image_url': jsonEncode([photo, photo, photo])
          }),
        ));
        await frames(tester);
        expect(
          tester.widget<CarPhoto>(find.byType(CarPhoto).first).fit,
          BoxFit.contain,
        );
        expect(
          Directionality.of(tester.element(find.byType(PageView).first)),
          TextDirection.ltr,
        );
        Object? error;
        await tester.runAsync(() => precacheImage(const NetworkImage(photo),
                tester.element(find.byType(CarDetailsPage)),
                onError: (e, stack) => error = e)
            .timeout(const Duration(seconds: 25)));
        expect(error, isNull,
            reason: 'Gallery acceptance requires a decoded photo');
        await frames(tester);
        await tester.tap(find.byType(CarPhoto).first);
        await frames(tester);
        expect(find.byType(PhotoGallery), findsOneWidget);
        expect(
          tester
              .widget<CarPhoto>(
                find
                    .descendant(
                      of: find.byType(PhotoGallery),
                      matching: find.byType(CarPhoto),
                    )
                    .first,
              )
              .fit,
          BoxFit.contain,
        );
        final gallery = find.byType(PhotoGallery);
        expect(find.descendant(of: gallery, matching: find.text('1 / 3')),
            findsOneWidget);
        final decoded = find.descendant(
            of: gallery,
            matching: find.byWidgetPredicate(
                (widget) => widget is RawImage && widget.image != null));
        for (var i = 0; i < 50 && decoded.evaluate().isEmpty; i++) {
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)));
          await frames(tester);
        }
        expect(decoded, findsWidgets);
        final labels = MaterialLocalizations.of(tester.element(gallery));
        await tester.tap(find.byTooltip(labels.nextPageTooltip));
        await frames(tester);
        expect(find.descendant(of: gallery, matching: find.text('2 / 3')),
            findsOneWidget);
        await currentTypographyCheckpoint(tester, 'CAR_GALLERY');
        final viewerFinder = find.byType(InteractiveViewer);
        final center = tester.getCenter(viewerFinder);
        final first = await tester.createGesture(pointer: 1);
        final second = await tester.createGesture(pointer: 2);
        await first.down(center - const Offset(50, 0));
        await second.down(center + const Offset(50, 0));
        await first.moveTo(center - const Offset(150, 0));
        await second.moveTo(center + const Offset(150, 0));
        await tester.pump();
        await first.up();
        await second.up();
        await frames(tester);
        final viewer = tester.widget<InteractiveViewer>(viewerFinder);
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
            greaterThan(1.1));
        await tester.drag(viewerFinder, const Offset(-100, 40));
        await frames(tester);
        expect(find.descendant(of: gallery, matching: find.text('2 / 3')),
            findsOneWidget);
        await currentTypographyCheckpoint(tester, 'CAR_GALLERY_ZOOM');
        await tester.tap(find.byTooltip(t('ui_reset_zoom')));
        await frames(tester);
        expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
        final bounds = tester.getRect(find.byType(PageView).last);
        await tester.dragFrom(
            Offset(bounds.left + bounds.width * .8, bounds.center.dy),
            Offset(-bounds.width * .6, 0));
        await frames(tester);
        expect(find.descendant(of: gallery, matching: find.text('3 / 3')),
            findsOneWidget);
        await tester.tap(find.byTooltip(labels.previousPageTooltip));
        await frames(tester);
        expect(find.descendant(of: gallery, matching: find.text('2 / 3')),
            findsOneWidget);
        await tester.tap(find.byType(CloseButton));
        await frames(tester);
        expect(gallery, findsNothing);
        expect(find.byType(CarDetailsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }, skip: !native);
    }
  }
}
