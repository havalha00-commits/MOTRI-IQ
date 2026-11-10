import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/search/smart_query.dart';
import 'package:motri_iq/search/saved_search_criteria.dart';
import 'package:motri_iq/ui/search_filters_sheet.dart';
import 'support/current_typography_checkpoint.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  test('typed make and year become equivalent alert predicates', () {
    final result = savedSearchCriteria(
        query: 'نيسان ٢٠٢٢',
        quick: CarSearchFilters()
          ..fromYear = '2020'
          ..toYear = '2024',
        advanced: CarSearchFilters()
          ..minPrice = '١٠٬٠٠٠'
          ..maxPrice = '25000');
    expect(result.error, isNull);
    expect(result.payload, containsPair('brand', 'Nissan'));
    expect(result.payload, containsPair('min_year', 2022));
    expect(result.payload, containsPair('max_year', 2022));
    expect(result.payload, containsPair('query_text', null));
    expect(result.payload, containsPair('min_price', 10000));
  });
  for (final query in [
    'Camry',
    'Toyota Kia',
    'Toyota Baghdad',
    'Petrol',
    '2022 2023'
  ]) {
    test('unrepresentable smart query is explained: $query', () {
      final result = savedSearchCriteria(
          query: query,
          quick: CarSearchFilters(),
          advanced: CarSearchFilters());
      expect(result.payload, isNull);
      expect(result.error, 'ui_alert_criteria_limit');
    });
  }
  test('structured regional OR matching is not silently reduced to equality',
      () {
    final result = savedSearchCriteria(
        query: '',
        quick: CarSearchFilters(),
        advanced: CarSearchFilters()..province = 'Baghdad');
    expect(result.error, 'ui_alert_criteria_limit');
    final exact = savedSearchCriteria(
        query: '',
        advanced: CarSearchFilters(),
        quick: CarSearchFilters()..province = 'Baghdad');
    expect(exact.payload, containsPair('province', 'Baghdad'));
  });
  test('independent quick and advanced numeric bounds retain intersection', () {
    final result = savedSearchCriteria(
        query: '',
        quick: CarSearchFilters()
          ..minPrice = '10000'
          ..maxPrice = '20000',
        advanced: CarSearchFilters()
          ..minPrice = '12000'
          ..maxPrice = '18000');
    expect(result.payload, containsPair('min_price', 12000));
    expect(result.payload, containsPair('max_price', 18000));
    final conflict = savedSearchCriteria(
        query: 'Toyota',
        quick: CarSearchFilters()..brand = 'Kia',
        advanced: CarSearchFilters());
    expect(conflict.error, 'ui_alert_criteria_limit');
  });
  test('integer boundaries and nonfinite decimals cannot enter filter plans',
      () {
    expect((CarSearchFilters()..fromYear = '2147483647').numericError, isNull);
    expect((CarSearchFilters()..fromYear = '2147483648').numericError,
        'search_invalid_number');
    expect((CarSearchFilters()..maxMileage = '9' * 500).numericError,
        'search_invalid_number');
    expect((CarSearchFilters()..minPrice = '9' * 500).numericError,
        'search_invalid_number');
    expect(
        (CarSearchFilters()
              ..fromYear = '٢٠٢٥'
              ..toYear = '۲۰۲۰')
            .numericError,
        'search_invalid_year_range');
  });
  for (final locale in AppLocale.values) {
    testWidgets('${locale.code} oversized filters retain draft and recover',
        (tester) async {
      appLocaleNotifier.value = locale;
      AppColors.isDark = locale == AppLocale.ku;
      if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
      }
      CarSearchFilters? applied;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
            AppColors.isDark ? Brightness.dark : Brightness.light),
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.4)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => Center(
                    child: TextButton(
                        onPressed: () async {
                          applied =
                              await showModalBottomSheet<CarSearchFilters>(
                                  context: context,
                                  isScrollControlled: true,
                                  useSafeArea: true,
                                  builder: (_) => SearchFiltersSheet(
                                      initial: CarSearchFilters(),
                                      provinces: const [],
                                      fuels: const [],
                                      transmissions: const []));
                        },
                        child: const Text('Open'))))),
      ));
      await frames(tester);
      await tester.tap(find.text('Open'));
      await frames(tester);
      for (final field in [
        'fromYear',
        'toYear',
        'minPrice',
        'maxPrice',
        'maxMileage'
      ]) {
        final target = find.byKey(ValueKey('filter_$field'));
        await tester.ensureVisible(target);
        await frames(tester);
        final invalid = field == 'fromYear' || field == 'maxMileage'
            ? '2147483648'
            : '9' * 500;
        await tester.enterText(target, invalid);
        await tester.tap(find.text(t('search_apply')));
        await frames(tester);
        expect(applied, isNull);
        expect(find.text(t('search_invalid_number')), findsOneWidget);
        expect(tester.widget<TextField>(target).controller!.text, invalid);
        expect(tester.takeException(), isNull);
        if (field == 'maxMileage') {
          await currentTypographyCheckpoint(tester, 'FILTER_INVALID');
        }
        await tester.enterText(target, '');
      }
      await tester.enterText(
          find.byKey(const ValueKey('filter_maxMileage')), '٢٥٬٠٠٠');
      await tester.tap(find.text(t('search_apply')));
      await frames(tester);
      expect(applied!.maxMileage, '25000');
      expect(find.byType(SearchFiltersSheet), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
  }
}
