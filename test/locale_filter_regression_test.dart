import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/search/search_vocabulary.dart';
import 'package:motri_iq/search/business_categories.dart';
import 'package:motri_iq/ui/search_filters_sheet.dart';
import 'package:motri_iq/l10n/app_strings.dart';

Widget host(Widget page) => ValueListenableBuilder<AppLocale>(
      key: UniqueKey(),
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) => MaterialApp(
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) =>
            AppStringsScope(locale: locale, child: child!),
        home: page,
      ),
    );
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co', publishableKey: 'test');
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
  });
  testWidgets('selected business filter survives changing language',
      (tester) async {
    await tester.pumpWidget(host(const BusinessAdsPage()));
    await frames(tester);
    final filter = find.byType(DropdownButtonFormField<String>);
    expect(tester.state<FormFieldState<String>>(filter).value, '');
    await tester.tap(filter);
    await frames(tester);
    await tester.tap(find.text(t('svc_parts')).last);
    await frames(tester);
    expect(tester.state<FormFieldState<String>>(filter).value, 'svc_parts');
    await setAppLocale(AppLocale.en);
    await frames(tester);
    expect(tester.state<FormFieldState<String>>(filter).value, 'svc_parts');
    expect(find.text(t('svc_parts')), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'applying focused advanced filters does not dispose live text fields',
      (tester) async {
    await tester.pumpWidget(host(const Scaffold(body: SearchTab())));
    await frames(tester);
    final state = tester.state<SearchTabState>(find.byType(SearchTab));
    state.vocabulary = SearchVocabulary(
        brands: [],
        models: [],
        composites: [],
        cities: [],
        provinces: [],
        fuels: [],
        transmissions: [],
        bodyTypes: []);
    await tester.tap(find.byTooltip(t('search_filters_title')));
    await frames(tester);
    await tester.enterText(
        find.widgetWithText(TextField, t('field_brand')).last, 'Toyota');
    await tester.ensureVisible(find.text(t('search_apply')));
    await tester.tap(find.text(t('search_apply')));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(state.advanced.brand, 'Toyota');
  });
  for (final locale in AppLocale.values) {
    testWidgets('${locale.code}: invalid ranges, apply, dismiss and reset',
        (tester) async {
      appLocaleNotifier.value = locale;
      await tester.pumpWidget(host(const Scaffold(body: SearchTab())));
      await frames(tester);
      final state = tester.state<SearchTabState>(find.byType(SearchTab));
      await tester.tap(find.byTooltip(t('search_filters_title')));
      await frames(tester);
      await tester.enterText(
          find.byKey(const ValueKey('filter_fromYear')), '٢٠٢٥');
      await tester.enterText(
          find.byKey(const ValueKey('filter_toYear')), '٢٠٢٠');
      await tester.tap(find.text(t('search_apply')));
      await frames(tester);
      expect(find.text(t('search_invalid_year_range')), findsOneWidget);
      expect(state.advanced.isEmpty, isTrue);
      await tester.enterText(
          find.byKey(const ValueKey('filter_toYear')), '٢٠٢٦');
      await tester.tap(find.text(t('search_apply')));
      await frames(tester);
      expect(state.advanced.fromYear, '2025');
      expect(state.advanced.toYear, '2026');
      await tester.tap(find.byTooltip(t('search_filters_title')));
      await frames(tester);
      await tester.enterText(
          find.byKey(const ValueKey('filter_brand')), 'discard this draft');
      await tester.tap(find.descendant(
          of: find.byType(SearchFiltersSheet),
          matching: find.byIcon(Icons.close_rounded)));
      await frames(tester);
      expect(state.advanced.brand, isEmpty);
      expect(state.advanced.fromYear, '2025');
      await tester.tap(find.byTooltip(t('search_filters_title')));
      await frames(tester);
      await tester.tap(find.text(t('search_reset')));
      await frames(tester);
      expect(state.advanced.isEmpty, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dropdown deduplicates options and follows programmatic reset',
      (tester) async {
    var value = 'Diesel';
    late StateSetter update;
    await tester.pumpWidget(
        host(Scaffold(body: StatefulBuilder(builder: (context, setState) {
      update = setState;
      return StableFilterDropdown(
          label: 'Fuel',
          value: value,
          options: const ['', 'Diesel', 'Diesel'],
          onChanged: (v) => setState(() => value = v));
    }))));
    await frames(tester);
    expect(tester.takeException(), isNull);
    update(() => value = '');
    await frames(tester);
    expect(
        tester
            .widget<DropdownButtonFormField<String>>(
                find.byType(DropdownButtonFormField<String>))
            .initialValue,
        '');
    expect(tester.takeException(), isNull);
  });

  testWidgets('filter footer stays accessible above keyboard on small phones',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const Scaffold(body: SearchTab())));
    await frames(tester);
    await tester.tap(find.byTooltip(t('search_filters_title')));
    await frames(tester);
    tester.view.viewInsets = FakeViewPadding(bottom: 300);
    await frames(tester);
    expect(tester.takeException(), isNull);
    final footer = tester.getRect(find.text(t('search_apply')));
    expect(footer.bottom, lessThan(340));
  });

  test('business category selection and query values are locale-independent',
      () {
    final values = BusinessCategories.storedValues;
    for (final locale in AppLocale.values) {
      appLocaleNotifier.value = locale;
      expect(BusinessCategories.storedValues, values);
      expect(BusinessCategories.queryValues(t('common_all')), isEmpty);
      expect(BusinessCategories.queryValues('svc_parts'),
          contains(AppStrings.t('svc_parts', locale.code)));
      expect(BusinessCategories.keyFor(AppStrings.t('svc_parts', locale.code)),
          'svc_parts');
    }
  });
  testWidgets(
      'actual language picker can switch repeatedly without route errors',
      (tester) async {
    await tester.pumpWidget(host(const HomePage()));
    await frames(tester);
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(5);
    await frames(tester);
    for (final locale in [
      AppLocale.ar,
      AppLocale.ku,
      AppLocale.en,
      AppLocale.ar,
      AppLocale.en
    ]) {
      await tester.tap(find.byTooltip(t('account_language')));
      await frames(tester);
      await tester.tap(find.text(locale.label));
      await frames(tester);
      expect(appLocale, locale);
      expect(tester.takeException(), isNull);
    }
  });
}
