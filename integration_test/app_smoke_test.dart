import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:motri_iq/main.dart' as app;
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/ui/search_filters_sheet.dart';

Future<void> advance(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  // Public listing requests can take longer than the previous six-second
  // bound on a cold emulator; keep the wait finite without skipping checks.
  for (var i = 0; i < 300 && finder.evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(finder, findsWidgets);
}

Future<void> tab(WidgetTester tester, String label) async {
  final finder = find.descendant(
      of: find.byType(NavigationBar), matching: find.text(t(label)));
  await tester.tap(finder);
  await advance(tester);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('mobile guest journeys, navigation and all three locales',
      (tester) async {
    await app.main();
    await waitFor(tester, find.byType(app.HomePage));
    final originalLocale = appLocale;
    try {
      for (final locale in AppLocale.values) {
        debugPrint(
            'Reviewing ${locale.code} navigation, listing, settings and support');
        await tab(tester, 'nav_account');
        await tester.tap(find.byTooltip(t('account_language')));
        await advance(tester);
        await tester.tap(find.text(locale.label));
        await advance(tester);
        expect(appLocale, locale);
        await tab(tester, 'nav_search');
        expect(find.byType(app.SearchTab), findsOneWidget);
        if (locale == AppLocale.ar &&
            const bool.fromEnvironment('SEARCH_REVIEW_HOLD')) {
          debugPrint('SEARCH_HEADER_VISUAL');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        expect(Directionality.of(tester.element(find.byType(TextField).first)),
            locale.direction);
        await tester.tap(find.byTooltip(t('search_filters_title')));
        await advance(tester);
        await tester.enterText(
            find.byKey(const ValueKey('filter_brand')), 'Toyota');
        await tester.tap(find.text(t('search_apply')));
        await advance(tester);
        expect(find.byType(SearchFiltersSheet), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip(t('search_filters_title')));
        await advance(tester);
        expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('filter_brand')))
                .controller!
                .text,
            'Toyota');
        await tester.enterText(
            find.byKey(const ValueKey('filter_brand')), 'Discard');
        await tester.tap(find.descendant(
            of: find.byType(SearchFiltersSheet),
            matching: find.byIcon(Icons.close_rounded)));
        await advance(tester);
        await tester.tap(find.byTooltip(t('search_filters_title')));
        await advance(tester);
        expect(
            tester
                .widget<TextField>(find.byKey(const ValueKey('filter_brand')))
                .controller!
                .text,
            'Toyota');
        await tester.tap(find.text(t('search_reset')));
        await advance(tester);
        expect(
            tester
                .state<app.SearchTabState>(find.byType(app.SearchTab))
                .advanced
                .isEmpty,
            isTrue);
        expect(tester.takeException(), isNull);
        await tab(tester, 'nav_cars');
        expect(find.byType(app.SectionPage), findsOneWidget);
        if (locale == AppLocale.ar) {
          await waitFor(tester, find.byType(app.CarCard));
          await tester.tap(find.byType(app.CarCard).first);
          await advance(tester);
          expect(find.byType(app.CarDetailsPage), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.byType(BackButton));
          await advance(tester);
        }
        await tab(tester, 'nav_market');
        await waitFor(tester, find.text(t('home_latest_market')));
        expect(find.byType(app.HomeTab), findsOneWidget);
        await tab(tester, 'nav_account');
        expect(find.byType(app.AccountTab), findsOneWidget);
        await tester.tap(find.byTooltip(t('settings_title')));
        await advance(tester);
        expect(find.byType(app.SettingsPage), findsOneWidget);
        final settingsScaffold = find.descendant(
            of: find.byType(app.SettingsPage), matching: find.byType(Scaffold));
        expect(Directionality.of(tester.element(settingsScaffold)),
            locale.direction);
        if (locale == AppLocale.ar) {
          final wasDark = app.AppColors.isDark;
          await tester.tap(find.byType(Switch).last);
          await advance(tester);
          expect(app.AppColors.isDark, !wasDark);
          await tester.tap(find.byType(Switch).last);
          await advance(tester);
          expect(app.AppColors.isDark, wasDark);
        }
        await tester.ensureVisible(find.text(t('settings_about')));
        await tester.tap(find.text(t('settings_about')));
        await advance(tester);
        expect(find.byType(app.AboutPage), findsOneWidget);
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        await tester.tap(find.byType(BackButton));
        await advance(tester);
        await tester.tap(find.byType(BackButton));
        await advance(tester);
        await tester.tap(find.byTooltip(t('account_support_center')));
        await advance(tester);
        expect(find.byType(app.SupportCenterPage), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await advance(tester);
        expect(tester.takeException(), isNull);
      }
      // Exercise the actual language chooser, including its radio callbacks.
      await tester.tap(find.byTooltip(t('account_language')));
      await advance(tester);
      await tester.tap(find.text(AppLocale.ar.label));
      await advance(tester);
      expect(appLocale, AppLocale.ar);
      await tab(tester, 'nav_add');
      expect(find.byType(app.AddCarTab), findsOneWidget);
      await tab(tester, 'nav_home');
      expect(find.byType(app.HomeTab), findsOneWidget);
      final homeList = find
          .descendant(
              of: find.byType(app.HomeTab), matching: find.byType(ListView))
          .first;
      tester.widget<ListView>(homeList).controller?.jumpTo(0);
      await advance(tester);
      await tester.drag(homeList, const Offset(0, 400));
      await advance(tester);
      // Drive frames while the refresh animation and read requests finish.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
    } finally {
      await setAppLocale(originalLocale);
    }
  });
}
