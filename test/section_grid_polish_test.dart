import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/design/app_icons.dart';
import 'package:motri_iq/ui/compact_listing_card.dart';
import 'package:motri_iq/ui/app_state_panel.dart';
import 'support/current_typography_checkpoint.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> row(int index) => {
      'id': 'grid-$index',
      'brand': 'Toyota',
      'model': 'Land Cruiser Platinum extended model name $index',
      'year': 2025,
      'price': 73000,
      'city': 'بغداد',
      'province': 'بغداد',
      'mileage_km': 123456,
      'image_url': ''
    };
http.Response reply(http.Request req, Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  final gets = <http.Request>[], writes = <http.Request>[];
  late Future<http.Response> Function(http.Request) load;
  var favorite = false, noAck = false, failWrite = false;
  Completer<void>? writeGate;
  const uid = '00000000-0000-4000-8000-000000000001';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': uid,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final signature = base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((req) async {
          if (req.url.path == '/auth/v1/token') {
            return reply(req, {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            });
          }
          if (req.url.path.endsWith('/cars_public') ||
              req.url.path.endsWith('/market_items')) {
            gets.add(req);
            return load(req);
          }
          if (req.url.path.endsWith('/favorites')) {
            if (req.method == 'GET') {
              return reply(
                  req,
                  favorite
                      ? [
                          {'car_id': 'grid-0'}
                        ]
                      : []);
            }
            writes.add(req);
            if (writeGate != null) await writeGate!.future;
            if (failWrite) {
              return reply(
                  req, {'message': 'private failure detail', 'code': 'XX000'},
                  status: 500);
            }
            if (noAck) return reply(req, []);
            favorite = req.method != 'DELETE';
            return reply(req, [
              {'car_id': 'grid-0'}
            ]);
          }
          return reply(req, []);
        }));
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() {
    gets.clear();
    writes.clear();
    favorite = noAck = failWrite = false;
    writeGate = null;
    load = (req) async => reply(req, [row(0), row(1)]);
    backendApi = BackendApi(
      baseUrl: 'https://test.invalid',
      accessToken: () => 'test-token',
      accessTokenAsync: () async => 'test-token',
      backendAccessToken: () => 'test-token',
      backendAccessTokenAsync: () async => 'test-token',
      client: MockClient((req) async {
        if (req.url.path.endsWith('/cars') ||
            req.url.path.endsWith('/market/items')) {
          gets.add(req);
        }
        final response = await load(req);
        if (response.statusCode >= 400) return response;
        final body = jsonDecode(response.body);
        if (body is List) {
          return reply(req, {'success': true, 'data': body});
        }
        return response;
      }),
    );
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
    trustCache.reset();
    compareCars.value = [];
  });
  Future<void> mount(WidgetTester tester,
      {Widget? page, double scale = 1, double width = 390}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = Size(width, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        theme: buildAppTheme(
            AppColors.isDark ? Brightness.dark : Brightness.light),
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: page ??
            const SectionPage(title: kSectionCars, icon: AppIcons.cars)));
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('section grid ${locale.code} dark=$dark scale=$scale',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          await mount(tester, scale: scale);
          expect(find.byType(CompactListingCard), findsWidgets);
          final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
          final delegate =
              grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            expect(delegate.crossAxisCount, scale > 1 ? 1 : 2);
          }
          expect(find.text(formatUsd(73000)), findsWidgets);
          expect(find.text(formatIqd(95630000)), findsWidgets);
          if (scale > 1) {
            await currentTypographyCheckpoint(tester, 'SECTION_CARS_GRID');
          }
          expect(
              find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == t('ad_saved_deal')),
              findsNothing);
          expect(
              find.byWidgetPredicate(
                  (w) => w is IconButton && w.tooltip == t('ad_compare')),
              findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('market states ${locale.code} dark=$dark large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final gate = Completer<http.Response>();
        load = (req) => gate.future;
        await mount(tester,
            scale: 1.6,
            width: 320,
            page: const SectionPage(
                title: kSectionMarket, icon: AppIcons.market));
        expect(find.byType(AppLoadingView), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'MARKET_LOADING');
        gate.complete(reply(gets.last, []));
        await frames(tester);
        expect(find.text(t('market_no_ads')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'MARKET_EMPTY');
        load = (req) async =>
            reply(req, {'message': 'private diagnostic'}, status: 500);
        await tester
            .widget<RefreshIndicator>(find.byType(RefreshIndicator))
            .onRefresh();
        await frames(tester);
        expect(find.text(t('ui_load_error_title')), findsOneWidget);
        expect(find.textContaining('private diagnostic'), findsNothing);
        await currentTypographyCheckpoint(tester, 'MARKET_ERROR');
        load = (req) async => reply(req, [
              {
                'id': 'market-english',
                'title': 'Original wheels (2025)',
                'price': 1250,
                'city': 'Baghdad'
              },
              {
                'id': 'market-arabic',
                'title': 'قطع غيار أصلية',
                'price': 500,
                'city': 'بغداد'
              },
            ]);
        await tester.tap(find.text(t('ui_retry')));
        await frames(tester);
        expect(gets.last.url.path, endsWith('/market/items'));
        final cards = tester
            .widgetList<CompactListingCard>(find.byType(CompactListingCard))
            .toList();
        expect(cards.first.titleDirection, TextDirection.ltr);
        expect(cards.first.primaryPrice, formatUsd(1250));
        final list =
            tester.widget<CustomScrollView>(find.byType(CustomScrollView));
        list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
        await frames(tester);
        expect(
            tester
                .widgetList<CompactListingCard>(find.byType(CompactListingCard))
                .firstWhere((c) => c.title == 'قطع غيار أصلية')
                .titleDirection,
            TextDirection.rtl);
        list.controller!.jumpTo(0);
        await frames(tester);
        await currentTypographyCheckpoint(tester, 'MARKET_GRID');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets(
      'embedded Cars uses the shell Add action while standalone keeps its own',
      (tester) async {
    await mount(tester,
        page: const SectionPage(
            title: kSectionCars, icon: AppIcons.cars, showAddAction: false));
    expect(find.byType(FloatingActionButton), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await mount(tester);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'previous asking price remains visible without flattening price hierarchy',
      (tester) async {
    await mount(tester,
        page: Scaffold(
            body: SizedBox(
                width: 200,
                height: 340,
                child: CarCard(
                    square: true, car: {...row(0), 'original_price': 75000}))));
    final prior = tester.widget<Text>(find.text(formatUsd(75000)));
    final current = tester.widget<Text>(find.text(formatUsd(73000)));
    expect(prior.style!.decoration, TextDecoration.lineThrough);
    expect(current.style!.fontSize!, greaterThan(prior.style!.fontSize!));
    expect(tester.takeException(), isNull);
  });
  testWidgets('initial failure retries to empty scrollable state',
      (tester) async {
    load = (req) async =>
        reply(req, {'message': 'offline', 'code': 'XX000'}, status: 500);
    await mount(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    load = (req) async => reply(req, []);
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('misc_no_ads_now')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'pagination duplicate guard, failed cursor retry, and ID deduplication',
      (tester) async {
    final gate = Completer<http.Response>();
    var fail = true;
    load = (req) async {
      final offset = int.parse(req.url.queryParameters['offset'] ?? '0');
      if (offset == 0) return reply(req, List.generate(30, row));
      if (fail) return gate.future;
      return reply(req, [row(29), row(30)]);
    };
    await mount(tester);
    final list = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await frames(tester);
    final count = gets.length;
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await frames(tester);
    expect(gets.length, count);
    expect(gets.last.url.queryParameters['offset'], '30');
    gate.complete(
        reply(gets.last, {'message': 'offline', 'code': 'XX000'}, status: 500));
    await frames(tester);
    expect(find.byKey(const ValueKey('section_more_error')), findsOneWidget);
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await frames(tester);
    expect(gets.length, count);
    fail = false;
    final retry = find.descendant(
        of: find.byKey(const ValueKey('section_more_error')),
        matching: find.text(t('ui_retry')));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await frames(tester);
    expect(gets.last.url.queryParameters['offset'], '30');
    expect(gets.last.url.queryParameters['limit'], '30');
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await frames(tester);
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-30'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('section_more_error')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'refresh wins over pending page and failure retains previous rows',
      (tester) async {
    final gate = Completer<http.Response>();
    var more = false;
    load = (req) async {
      if (req.url.queryParameters['offset'] == '30') {
        more = true;
        return gate.future;
      }
      return reply(req, List.generate(30, row));
    };
    await mount(tester);
    final list = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
    list.controller!.jumpTo(list.controller!.position.maxScrollExtent);
    await frames(tester);
    expect(more, isTrue);
    load = (req) async => reply(req, [row(99)]);
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    unawaited(refresh.onRefresh());
    await frames(tester);
    gate.complete(reply(gets.first, [row(31)]));
    await frames(tester);
    list.controller!.jumpTo(0);
    await frames(tester);
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-99'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-31'),
        findsNothing);
    load = (req) async =>
        reply(req, {'message': 'offline', 'code': 'XX000'}, status: 500);
    unawaited(refresh.onRefresh());
    await frames(tester);
    expect(find.text(t('ui_previous_list')), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-99'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'brand change replaces pending results and handles a long toolbar',
      (tester) async {
    final gate = Completer<http.Response>();
    final brand = ValueNotifier<String>('Toyota');
    addTearDown(brand.dispose);
    load = (req) => req.url.queryParameters['brand'] == 'Toyota'
        ? gate.future
        : Future.value(reply(req, [
            {...row(2), 'brand': 'Kia'}
          ]));
    await mount(tester,
        scale: 1.6,
        page: ValueListenableBuilder<String>(
            valueListenable: brand,
            builder: (context, value, child) => SectionPage(
                title: kSectionCars, icon: AppIcons.cars, brand: value)));
    brand.value = 'Kia';
    await frames(tester);
    gate.complete(reply(gets.first, [row(1)]));
    await frames(tester);
    expect(gets.last.url.queryParameters['brand'], 'Kia');
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-2'),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is CarCard && w.car['id'] == 'grid-1'),
        findsNothing);
    brand.value =
        'Kia with an exceptionally long brand qualifier for toolbar layout';
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('favorite and compare controls live in ad details, not cards',
      (tester) async {
    await mount(tester,
        page: CarDetailsPage(car: {
          ...row(0),
          'image_url': 'https://example.test/car.jpg',
        }));

    Finder action(String key) =>
        find.byWidgetPredicate((w) => w is IconButton && w.tooltip == t(key));
    final favoriteAction = action('ad_saved_deal');
    final compareAction = action('ad_compare');
    expect(favoriteAction, findsOneWidget);
    expect(compareAction, findsOneWidget);
    expect(
        tester.getSize(favoriteAction).shortestSide, greaterThanOrEqualTo(48));
    final photoRect = tester.getRect(find.byType(PageView).first);
    expect(photoRect.contains(tester.getCenter(favoriteAction)), isTrue);
    expect(photoRect.contains(tester.getCenter(compareAction)), isTrue);
    expect(
      tester.widget<CarPhoto>(find.byType(CarPhoto).first).fit,
      BoxFit.contain,
    );

    await tester.tap(favoriteAction);
    await frames(tester);
    expect(find.text(t('ad_login_to_fav')), findsOneWidget);

    await tester.tap(compareAction);
    expect(compareCars.value, hasLength(1));
    await tester.tap(compareAction);
    expect(compareCars.value, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'market summary prices follow locale and preserve nonnumeric labels',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ku;
    await mount(tester,
        page: const Scaffold(
            body: Column(children: [
          SizedBox(
              width: 200,
              height: 300,
              child: GenericAdCard(
                  item: {'id': 'm', 'title': 'Wheels', 'price': '٢٥٠'},
                  icon: AppIcons.market,
                  square: true)),
          SizedBox(
              width: 200,
              height: 300,
              child: GenericAdCard(
                  item: {'id': 'n', 'title': 'Seats', 'price': 'Negotiable'},
                  icon: AppIcons.market,
                  square: true)),
        ])));
    expect(find.text(formatUsd(250)), findsOneWidget);
    expect(find.text('Negotiable'), findsOneWidget);
    expect(find.textContaining('دولار'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('market listings remain visible after signing out',
      (tester) async {
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    load = (req) async => reply(req, [
          {
            'id': 'guest-market',
            'user_id': uid,
            'title': 'Guest-visible market listing',
            'price': 250,
            'images': [],
          }
        ]);
    await mount(
      tester,
      page: const SectionPage(title: kSectionMarket, icon: AppIcons.market),
    );
    expect(find.text('Guest-visible market listing'), findsOneWidget);
    expect(gets.last.url.path, endsWith('/market/items'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
