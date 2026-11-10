import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:motri_iq/main.dart' as app;
import 'package:motri_iq/l10n/app_locale.dart';

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

Future<void> captureReady(WidgetTester tester, String name,
    {bool photos = false}) async {
  final viewport =
      Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
  bool visible(Element element) {
    final box = element.renderObject;
    return box is RenderBox &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).overlaps(viewport);
  }

  // Photos are often non-interactive, so geometry determines visibility.
  if (photos) {
    var decoded = false;
    for (var i = 0; i < 450; i++) {
      final visiblePhotos =
          find.byType(app.CarPhoto).evaluate().where(visible).toList();
      decoded = visiblePhotos.isNotEmpty &&
          visiblePhotos.every((element) {
            final owner = find.byElementPredicate(
                (candidate) => identical(candidate, element));
            return find
                .descendant(of: owner, matching: find.byType(RawImage))
                .evaluate()
                .any((raw) => (raw.widget as RawImage).image != null);
          });
      if (decoded) break;
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(decoded, isTrue,
        reason: 'Visible listing photos must be rendered before capture.');
  }
  // Wait for visible data requests rather than accepting a timed placeholder.
  for (var i = 0; i < 300; i++) {
    final loading = find
            .byType(CircularProgressIndicator)
            .hitTestable()
            .evaluate()
            .isNotEmpty ||
        find
            .byType(LinearProgressIndicator)
            .hitTestable()
            .evaluate()
            .isNotEmpty;
    if (!loading && i >= 10) break;
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.byType(CircularProgressIndicator).hitTestable(), findsNothing);
  expect(find.byType(LinearProgressIndicator).hitTestable(), findsNothing);
  final images = find.byType(Image).evaluate().where(visible).toList();
  if (photos) expect(images, isNotEmpty);
  // Decode every visible image, and fail instead of capturing a broken image.
  for (final element in images) {
    final widget = element.widget as Image;
    final stream = widget.image.resolve(createLocalImageConfiguration(element));
    final ready = Completer<void>();
    final listener = ImageStreamListener(
      (_, synchronousCall) {
        if (!ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      await tester
          .runAsync(() => ready.future.timeout(const Duration(seconds: 30)));
    } finally {
      stream.removeListener(listener);
    }
  }
  await tester.pump(const Duration(milliseconds: 600));
  expect(tester.takeException(), isNull);
  debugPrint('PLAY_STORE_CAPTURE:$name');
  // The host captures this fully rendered frame while motion stays disabled.
  await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 4)));
}

Future<void> selectTab(WidgetTester tester, String key) async {
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.descendant(
      of: find.byType(NavigationBar), matching: find.text(t(key))));
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> openPage(WidgetTester tester, Widget page) async {
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  unawaited(navigator.push(MaterialPageRoute<void>(builder: (_) => page)));
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('eight full pages per supported language with loaded content',
      (tester) async {
    await app.main();
    final originalLocale = appLocale;
    final originalDark = app.AppColors.isDark;
    final originalCompare = app.compareCars.value;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    Future<void> back() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).pop();
      await tester.pump(const Duration(milliseconds: 600));
    }

    try {
      await app.setDarkMode(false);
      await waitFor(tester, find.byType(NavigationBar));
      for (final locale in [AppLocale.ar, AppLocale.en, AppLocale.ku]) {
        await setAppLocale(locale);
        await selectTab(tester, 'nav_home');
        await waitFor(tester, find.byType(app.CarMarqueeStrip));
        await captureReady(tester, '${locale.code}/01-home', photos: true);
        await selectTab(tester, 'nav_cars');
        await waitFor(tester, find.byType(app.CarCard));
        await captureReady(tester, '${locale.code}/02-cars', photos: true);
        final cars = tester
            .widgetList<app.CarCard>(find.byType(app.CarCard))
            .map((w) => w.car)
            .take(2)
            .toList();
        expect(cars.length, 2);
        app.compareCars.value = cars;
        await openPage(tester, const app.CompareCarsPage());
        await captureReady(tester, '${locale.code}/03-compare', photos: true);
        await back();
        await selectTab(tester, 'nav_search');
        tester
            .state<app.SearchTabState>(find.byType(app.SearchTab))
            .setQueryAndSearch(cars.first['brand'].toString());
        await tester.pump(const Duration(milliseconds: 500));
        await waitFor(tester, find.byType(app.CarCard));
        await captureReady(tester, '${locale.code}/04-search', photos: true);
        await openPage(tester, const app.SupportCenterPage());
        await captureReady(tester, '${locale.code}/05-support');
        await back();
        await openPage(tester, const app.AboutPage());
        await waitFor(tester, find.text('1.0.1'));
        await captureReady(tester, '${locale.code}/06-about');
        await back();
        await openPage(tester, const app.SettingsPage());
        await captureReady(tester, '${locale.code}/07-settings');
        await tester.tap(find.text(t('account_delete_title')));
        await tester.pump(const Duration(milliseconds: 600));
        await captureReady(tester, '${locale.code}/08-account-deletion');
        await back();
        await back();
      }
    } finally {
      app.compareCars.value = originalCompare;
      await setAppLocale(originalLocale);
      await app.setDarkMode(originalDark);
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      await tester.pump();
    }
  });
}
