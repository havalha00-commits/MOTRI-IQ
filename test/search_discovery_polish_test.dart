import 'support/current_typography_checkpoint.dart';
import 'dart:async';
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
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> car(String id) => {
      'id': id,
      'brand': 'Toyota',
      'model': 'Land Cruiser $id',
      'year': 2025,
      'price': 25000,
      'images': <String>[],
    };
http.Response response(http.Request request, Object data, {int status = 200}) =>
    http.Response(jsonEncode(data), status,
        request: request, headers: {'content-type': 'application/json'});

void main() {
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) cars;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          if (request.url.path.endsWith('/cars_public')) {
            requests.add(request);
            return cars(request);
          }
          return response(request, []);
        }));
  });
  setUp(() {
    requests.clear();
    cars = (request) async => response(request, []);
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
    trustCache.reset();
  });
  Future<SearchTabState> mount(WidgetTester tester, {double scale = 1}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
      theme:
          buildAppTheme(AppColors.isDark ? Brightness.dark : Brightness.light),
      locale: appLocale.locale,
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: const Scaffold(body: SafeArea(child: SearchTab())),
    ));
    await frames(tester);
    return tester.state<SearchTabState>(find.byType(SearchTab));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Search delayed query ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final gate = Completer<http.Response>();
        cars = (_) => gate.future;
        final state = await mount(tester, scale: 1.6);
        state.controller.text = 'Toyota';
        unawaited(state.search());
        await frames(tester);
        expect(state.loading, isTrue);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(t('search_no_matches')), findsNothing);
        expect(find.byKey(const ValueKey('search_error')), findsNothing);
        await tester.scrollUntilVisible(find.byType(CircularProgressIndicator), 200,
            scrollable: find.byType(Scrollable).first);
        await currentTypographyCheckpoint(tester, 'SEARCH_LOADING');
        gate.complete(response(requests.single, []));
        await frames(tester);
        expect(state.loading, isFalse);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text(t('search_no_matches')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets(
      'latest manual search wins; clearing invalidates pending requests',
      (tester) async {
    final gates = <Completer<http.Response>>[];
    cars = (request) {
      final gate = Completer<http.Response>();
      gates.add(gate);
      return gate.future;
    };
    final state = await mount(tester);
    state.controller.text = 'Toyota';
    unawaited(state.search());
    await frames(tester);
    state.controller.text = 'Kia';
    unawaited(state.search());
    await frames(tester);
    gates[1].complete(response(requests[1], [car('new')]));
    await frames(tester);
    expect(state.results.single['id'], 'new');
    gates[0].complete(response(requests[0], [car('old')]));
    await frames(tester);
    expect(state.results.single['id'], 'new');
    unawaited(state.search());
    await frames(tester);
    state.controller.clear();
    unawaited(state.search());
    gates[2].complete(response(requests[2], [car('obsolete')]));
    await frames(tester);
    expect(state.results, isEmpty);
    expect(state.hasMore, isFalse);
    expect(state.loading, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'obsolete errors cannot replace successful results after a filter change',
      (tester) async {
    final gate = Completer<http.Response>();
    cars = (request) => requests.length == 1
        ? gate.future
        : Future.value(response(request, [car('filtered')]));
    final state = await mount(tester);
    state.controller.text = 'Toyota';
    unawaited(state.search());
    await frames(tester);
    state.provinceFilter = 'بغداد';
    unawaited(state.search());
    await frames(tester);
    gate.complete(response(
        requests.first, {'message': 'old failure', 'code': 'XX000'},
        status: 500));
    await frames(tester);
    expect(state.searchFailed, isFalse);
    expect(state.results.single['id'], 'filtered');
    expect(requests.last.url.queryParameters['province'], 'eq.بغداد');
    expect(tester.takeException(), isNull);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Search recovery ${locale.code} dark=$dark failed then empty',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        cars = (request) async => response(
            request, {'message': 'offline', 'code': 'XX000'},
            status: 500);
        final state = await mount(tester, scale: 1.6);
        state.controller.text = 'Toyota';
        unawaited(state.search());
        await frames(tester);
        expect(state.searchFailed, isTrue);
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('search_error')), 300,
            scrollable: find.byType(Scrollable).first);
        await tester.pump();
        expect(find.text(t('search_no_matches')), findsNothing);
        if (!const bool.fromEnvironment('UI_SEARCH_POPULATED_ONLY')) {
          await currentTypographyCheckpoint(tester, 'SEARCH_ERROR');
        }
        if (const bool.fromEnvironment('UI_REVIEW_HOLD')) {
          debugPrint('SEARCH_ERROR_VISUAL');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        cars = (request) async => response(request, []);
        await tester.ensureVisible(find.text(t('ui_retry')));
        await tester.tap(find.text(t('ui_retry')));
        await frames(tester);
        expect(state.searchFailed, isFalse);
        expect(find.text(t('search_no_matches')), findsOneWidget);
        if (!const bool.fromEnvironment('UI_SEARCH_POPULATED_ONLY')) {
          await currentTypographyCheckpoint(tester, 'SEARCH_EMPTY');
        }
        cars = (request) async => response(request, [car('audit-result')]);
        unawaited(state.search());
        await frames(tester);
        expect(state.results.single['id'], 'audit-result');
        final card = find.byWidgetPredicate(
            (w) => w is CarCard && w.car['id'] == 'audit-result');
        await tester.scrollUntilVisible(card, 220,
            scrollable: find.byType(Scrollable).first);
        await frames(tester);
        expect(card, findsOneWidget);
        expect(find.text(t('search_no_matches')), findsNothing);
        await currentTypographyCheckpoint(tester, 'SEARCH_RESULT');
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'pagination retries cursor, deduplicates IDs and stops retry loops',
      (tester) async {
    var failMore = true;
    cars = (request) async {
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      if (offset == 0) {
        return response(request, List.generate(30, (i) => car('$i')));
      }
      if (failMore) {
        return response(request, {'message': 'offline', 'code': 'XX000'},
            status: 500);
      }
      return response(request, [car('29'), car('30')]);
    };
    final state = await mount(tester);
    state.controller.text = 'Toyota';
    unawaited(state.search());
    await frames(tester);
    state.scroll.jumpTo(state.scroll.position.maxScrollExtent);
    await frames(tester);
    expect(state.moreFailed, isTrue);
    expect(state.results.length, 30);
    final count = requests.length;
    state.scroll.jumpTo(state.scroll.position.maxScrollExtent);
    await frames(tester);
    expect(requests.length, count);
    failMore = false;
    await tester.ensureVisible(find.text(t('ui_retry')));
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(requests.last.url.queryParameters['offset'], '30');
    expect(state.results.length, 31);
    expect(state.hasMore, isFalse);
    expect(requests.last.url.queryParameters['order'], contains('id.desc'));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'quick filters parse localized numbers and reject reversed ranges',
      (tester) async {
    final state = await mount(tester);
    state.fromYear.text = '٢٠٢٠';
    state.toYear.text = '۲۰۲۵';
    state.minPrice.text = '١٠٬٠٠٠';
    unawaited(state.search());
    await frames(tester);
    expect(
        requests.last.url.queryParametersAll['year'], ['gte.2020', 'lte.2025']);
    expect(requests.last.url.queryParameters['price'], 'gte.10000.0');
    final count = requests.length;
    state.maxPrice.text = '٥٠٠';
    unawaited(state.search());
    await frames(tester);
    expect(requests.length, count);
    expect(find.text(t('search_invalid_price_range')), findsOneWidget);
  });
  testWidgets('single filter sheet preserves city and body type through apply',
      (tester) async {
    final state = await mount(tester);
    await tester.tap(find.byTooltip(t('search_filters_title')));
    await frames(tester);
    final city = find.byKey(const ValueKey('filter_city'));
    await tester.ensureVisible(city);
    await tester.enterText(city, 'بغداد');
    final body = find.byWidgetPredicate((w) =>
        w is DropdownButtonFormField<String> &&
        w.decoration.labelText == t('car_type'));
    await tester.ensureVisible(body);
    await tester.tap(body);
    await frames(tester);
    await tester.tap(find.text(vehicleBodyTypes.first).last);
    await frames(tester);
    await tester.tap(find.text(t('search_apply')));
    await frames(tester);
    expect(state.advanced.city, 'بغداد');
    expect(state.advanced.bodyType, vehicleBodyTypes.first);
    expect(requests.last.url.queryParameters['city'], 'ilike.%بغداد%');
    expect(requests.last.url.queryParameters['body_type'],
        'eq.${vehicleBodyTypes.first}');
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'Search filter draft ${locale.code} dark=$dark content direction',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final state = await mount(tester, scale: 1.6);
        await tester.tap(find.byTooltip(t('search_filters_title')));
        await frames(tester);
        final brand = find.byKey(const ValueKey('filter_brand'));
        final model = find.byKey(const ValueKey('filter_model'));
        final controller = tester.widget<TextField>(brand).controller!;
        const latin = TextEditingValue(
            text: 'Toyota',
            selection: TextSelection(baseOffset: 1, extentOffset: 4),
            composing: TextRange(start: 0, end: 6));
        controller.value = latin;
        await frames(tester);
        expect(
            tester.widget<TextField>(brand).textDirection, TextDirection.ltr);
        expect(controller.value, latin);
        await tester.enterText(model, 'لاند كروزر');
        await frames(tester);
        expect(
            tester.widget<TextField>(model).textDirection, TextDirection.rtl);
        expect(tester.widget<TextField>(brand).controller, same(controller));
        await currentTypographyCheckpoint(tester, 'SEARCH_FILTER_DRAFT');
        final year = find.byKey(const ValueKey('filter_fromYear'));
        await tester.ensureVisible(year);
        await tester.enterText(year, '٢٠٢٤');
        await frames(tester);
        expect(tester.widget<TextField>(year).textDirection, TextDirection.ltr);
        FocusManager.instance.primaryFocus?.unfocus();
        await frames(tester);
        await tester.tap(find.text(t('search_apply')));
        await frames(tester);
        expect(state.advanced.brand, 'Toyota');
        expect(state.advanced.model, 'لاند كروزر');
        expect(state.advanced.fromYear, '2024');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
      });
      testWidgets('Search header ${locale.code} dark=$dark enlarged text',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final state = await mount(tester, scale: 1.6);
        state.advanced
          ..brand = 'Toyota'
          ..city = locale == AppLocale.en ? 'Baghdad' : 'بغداد'
          ..fromYear = '2022'
          ..toYear = '2026';
        unawaited(state.search());
        await frames(tester);
        for (final label in state.advanced.activeLabels) {
          expect(find.widgetWithText(ActionChip, label), findsOneWidget);
        }
        final chipTheme =
            Theme.of(tester.element(find.byType(ActionChip).first)).chipTheme;
        expect(chipTheme.labelStyle?.fontFamily, 'MotriLatin');
        expect(chipTheme.labelStyle?.fontFamilyFallback,
            [locale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans']);
        await currentTypographyCheckpoint(tester, 'SEARCH_ACTIVE_CHIPS');
        expect(find.byKey(const ValueKey('search_discovery_header')),
            findsOneWidget);
        expect(find.byType(TextField), findsOneWidget,
            reason:
                'Criteria live in the filter sheet, not a duplicate inline form');
        final submit = tester.widget<IconButton>(find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == t('search')));
        final iconColor = (submit.icon as Icon).color!;
        final scheme = buildAppTheme(dark ? Brightness.dark : Brightness.light)
            .colorScheme;
        expect(iconColor, scheme.onPrimaryContainer);
        final foreground = iconColor.computeLuminance();
        final background = scheme.surface.computeLuminance();
        final ratio = foreground > background
            ? (foreground + .05) / (background + .05)
            : (background + .05) / (foreground + .05);
        expect(ratio, greaterThanOrEqualTo(3),
            reason: 'Submit icon stays visible in both themes');
        if (locale == AppLocale.ar &&
            !dark &&
            const bool.fromEnvironment('UI_REVIEW_HOLD')) {
          debugPrint('SEARCH_HEADER_VISUAL');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
