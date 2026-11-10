import 'support/current_typography_checkpoint.dart';
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
import 'package:motri_iq/market_images.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/search/business_categories.dart';

const photo =
    'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg';
Map<String, dynamic> row(String id, {bool images = false}) => {
      'id': id,
      'business_name': 'MOTRI Automotive service centre $id',
      'category': 'svc_parts',
      'status': 'active',
      'governorate': 'Baghdad',
      'area': 'Mansour',
      'description': 'Original parts and professional service. Open every day.',
      'phone': '07701234567',
      'whatsapp': '07701234567',
      'maps_url': 'https://maps.example.com/place',
      'instagram_url': 'https://instagram.example.com/shop',
      'image_urls': images ? [photo, '$photo?second=1'] : [],
      'working_hours': '09:00 – 18:00',
      'created_at': '2026-10-22T10:00:00Z'
    };
http.Response reply(http.Request req, Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'});
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  late Future<http.Response> Function(http.Request) load;
  final reads = <http.Request>[], analytics = <http.Request>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((req) async {
          if (req.method == 'POST') {
            analytics.add(req);
            return reply(req, null);
          }
          if (req.url.path.endsWith('/business_ads')) {
            reads.add(req);
            return load(req);
          }
          return reply(req, []);
        }));
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => null,
      client: MockClient((req) async {
        if (req.url.path.endsWith('/business-ads/active')) {
          final query = Map<String, String>.from(req.url.queryParameters);
          query['category'] = query.remove('categories') ?? '';
          final synthetic = http.Request(
            req.method,
            Uri.https('example.supabase.co', '/rest/v1/business_ads', query),
          );
          reads.add(synthetic);
          final response = await load(synthetic);
          if (response.statusCode < 200 || response.statusCode >= 300) {
            final body = jsonDecode(response.body);
            return reply(
              req,
              {'error': body is Map ? body['message'] : 'Failed to load ads'},
              status: response.statusCode,
            );
          }
          return reply(req, {'success': true, 'data': jsonDecode(response.body)});
        }
        analytics.add(req);
        return reply(req, {'success': true});
      }),
    );
  });
  setUp(() {
    reads.clear();
    analytics.clear();
    load = (req) async => reply(req, []);
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  Future<void> mount(WidgetTester tester, Widget page,
      {double scale = 1}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(
            AppColors.isDark ? Brightness.dark : Brightness.light),
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: page));
    await frames(tester);
  }

  Future<void> hold(WidgetTester tester, String name) async {
    if (!const bool.fromEnvironment('UI_REVIEW_HOLD')) return;
    debugPrint('REFERENCE_$name');
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Business photo detail ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final data = row('photo', images: true);
        await mount(
            tester, BusinessAdDetailsPage(ad: BusinessAdData.fromJson(data)),
            scale: 1.6);
        final bar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
        expect(bar.flexibleSpace, isNull);
        expect(find.byType(MarketItemGallery), findsOneWidget);
        if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          Object? imageError;
          await tester.runAsync(() => precacheImage(const NetworkImage(photo),
                  tester.element(find.byType(MarketItemGallery)),
                  onError: (error, _) => imageError = error)
              .timeout(const Duration(seconds: 25)));
          await frames(tester);
          expect(imageError, isNull);
        }
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'BUSINESS_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'BUSINESS_DETAIL');
        }
        await tester.scrollUntilVisible(find.text(data['description']), 220,
            scrollable: find.byType(Scrollable).first);
        await frames(tester);
        expect(tester.widget<Text>(find.text('09:00 – 18:00')).textDirection,
            TextDirection.ltr);
        expect(
            tester.widget<Text>(find.text(data['description'])).textDirection,
            TextDirection.ltr);
        await tester.scrollUntilVisible(find.text('WhatsApp'), 160,
            scrollable: find.byType(Scrollable).first);
        await frames(tester);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'BUSINESS_CONTACT_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'BUSINESS_CONTACT');
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final surface in ['loading', 'error', 'empty', 'populated']) {
        testWidgets(
            'Business discovery $surface ${locale.code} dark=$dark enlarged',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          final gate = Completer<http.Response>();
          http.Request? pending;
          load = (req) async {
            pending = req;
            if (surface == 'loading') return gate.future;
            if (surface == 'error') {
              return reply(
                  req, {'message': 'private diagnostics', 'code': 'XX000'},
                  status: 500);
            }
            return reply(req, surface == 'populated' ? [row('current')] : []);
          };
          await mount(tester, const BusinessAdsPage(), scale: 1.6);
          if (surface == 'loading') {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          } else if (surface == 'error') {
            expect(find.text(t('ui_load_error_title')), findsOneWidget);
            expect(find.textContaining('private diagnostics'), findsNothing);
          } else if (surface == 'empty') {
            expect(find.text(t('misc_no_business_ads')), findsOneWidget);
          } else {
            expect(find.byType(BusinessAdCard), findsOneWidget);
            for (final value in [
              row('current')['business_name'],
              row('current')['description'],
              'Baghdad · Mansour'
            ]) {
              final text = find.text(value);
              expect(text, findsOneWidget);
              expect(
                  tester.widget<Text>(text).textDirection, TextDirection.ltr);
            }
          }
          await currentTypographyCheckpoint(
              tester, 'BUSINESS_DISCOVERY_${surface.toUpperCase()}');
          if (surface == 'loading') {
            gate.complete(reply(pending!, []));
            await frames(tester);
            expect(find.text(t('misc_no_business_ads')), findsOneWidget);
          } else if (surface == 'error') {
            load = (req) async => reply(req, [row('recovered')]);
            await tester.tap(find.text(t('ui_retry')));
            await frames(tester);
            expect(find.byKey(const ValueKey('business_recovered')),
                findsOneWidget);
          } else if (surface == 'populated') {
            await tester.tap(find.byType(BusinessAdCard));
            await frames(tester);
            expect(find.byType(BusinessAdDetailsPage), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await frames(tester);
        });
      }
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'Business retained recovery ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final pageGate = Completer<http.Response>();
        http.Request? pending;
        var pageAttempts = 0, failRefresh = false;
        load = (req) async {
          if (req.url.queryParameters['offset'] == '20') {
            pageAttempts++;
            if (pageAttempts == 1) {
              pending = req;
              return pageGate.future;
            }
            return reply(req, [row('page-recovered')]);
          }
          return reply(
              req,
              failRefresh
                  ? {'message': 'private fixture failure', 'code': 'XX000'}
                  : [for (var i = 0; i < 20; i++) row('retained-$i')],
              status: failRefresh ? 500 : 200);
        };
        await mount(tester, const BusinessAdsPage(), scale: 1.6);
        final scroll =
            tester.state<ScrollableState>(find.byType(Scrollable).last);
        for (var i = 0; i < 6 && pending == null; i++) {
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await frames(tester);
        }
        expect(pending, isNotNull);
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await frames(tester);
        await currentTypographyCheckpoint(tester, 'BUSINESS_PAGE_LOADING');
        pageGate.complete(reply(
            pending!, {'message': 'private fixture failure'},
            status: 500));
        await frames(tester);
        final moreError = find.byKey(const ValueKey('business_more_error'));
        await tester.ensureVisible(moreError);
        await frames(tester);
        expect(find.text(t('ui_business_more_failed')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'BUSINESS_PAGE_ERROR');
        await tester.pump(const Duration(milliseconds: 300));
        expect(pageAttempts, 1,
            reason: 'Failed page does not retry automatically');
        final retry =
            find.descendant(of: moreError, matching: find.text(t('ui_retry')));
        await tester.ensureVisible(retry);
        await tester.tap(retry);
        await frames(tester);
        expect(pageAttempts, 2);
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await frames(tester);
        expect(find.byKey(const ValueKey('business_page-recovered')),
            findsOneWidget);
        scroll.position.jumpTo(0);
        await frames(tester);
        expect(
            find.byKey(const ValueKey('business_retained-0')), findsOneWidget);
        failRefresh = true;
        await tester.tap(find.byTooltip(t('alerts_update')));
        await frames(tester);
        expect(find.text(t('ui_business_refresh_failed')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('business_retained-0')), findsOneWidget);
        expect(find.textContaining('private'), findsNothing);
        await currentTypographyCheckpoint(tester, 'BUSINESS_REFRESH_ERROR');
        failRefresh = false;
        await tester.tap(find.text(t('ui_retry')));
        await frames(tester);
        expect(find.text(t('ui_business_refresh_failed')), findsNothing);
        expect(
            find.byKey(const ValueKey('business_retained-0')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
      });
    }
  }
  testWidgets(
      'blank Business logo and invalid photo values do not reserve a gallery',
      (tester) async {
    final data = row('no-photo')
      ..['logo_url'] = ' '
      ..['image_urls'] = ['', 'null'];
    await mount(
        tester, BusinessAdDetailsPage(ad: BusinessAdData.fromJson(data)));
    expect(find.byType(MarketItemGallery), findsNothing);
    expect(tester.widget<SliverAppBar>(find.byType(SliverAppBar)).flexibleSpace,
        isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('blank Business detail name uses the same fallback as its card',
      (tester) async {
    final data = BusinessAdData.fromJson(row('blank')..['business_name'] = ' ');
    await mount(tester, BusinessAdDetailsPage(ad: data));
    expect(find.text(t('common_unspecified')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final oldFails in [false, true]) {
    testWidgets(
        'latest Business category wins over a delayed old response failure=$oldFails',
        (tester) async {
      appLocaleNotifier.value = AppLocale.ku;
      AppColors.isDark = true;
      final gate = Completer<http.Response>();
      http.Request? pending;
      load = (req) async {
        final category = req.url.queryParameters['category'] ?? '';
        if (BusinessCategories.queryValues('svc_parts')
            .any(category.contains)) {
          pending = req;
          return gate.future;
        }
        return reply(
            req,
            BusinessCategories.queryValues('svc_tires').any(category.contains)
                ? [row('new-tires')]
                : []);
      };
      await mount(tester, const BusinessAdsPage(), scale: 1.6);
      Future<void> choose(String key) async {
        await tester.tap(find.byType(DropdownButtonFormField<String>));
        await frames(tester);
        await tester.tap(find.text(t(key)).last);
        await frames(tester);
      }

      await choose('svc_parts');
      expect(pending, isNotNull);
      await choose('svc_tires');
      expect(find.byKey(const ValueKey('business_new-tires')), findsOneWidget);
      gate.complete(reply(
          pending!,
          oldFails
              ? {'message': 'private diagnostics', 'code': 'XX000'}
              : [row('stale-parts')],
          status: oldFails ? 500 : 200));
      await frames(tester);
      expect(find.byKey(const ValueKey('business_new-tires')), findsOneWidget);
      expect(find.byKey(const ValueKey('business_stale-parts')), findsNothing);
      expect(find.text(t('ui_load_error_title')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'refresh invalidates a delayed Business page and does not append stale rows',
      (tester) async {
    final gate = Completer<http.Response>();
    http.Request? pending;
    var refreshed = false;
    load = (req) async {
      if (req.url.queryParameters['offset'] == '20') {
        pending = req;
        return gate.future;
      }
      return reply(
          req,
          refreshed
              ? [row('fresh')]
              : [for (var i = 0; i < 20; i++) row('old-$i')]);
    };
    await mount(tester, const BusinessAdsPage());
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
    for (var i = 0; i < 5 && pending == null; i++) {
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await frames(tester);
    }
    expect(pending, isNotNull);
    refreshed = true;
    await tester.tap(find.byTooltip(t('alerts_update')));
    await frames(tester);
    expect(find.byKey(const ValueKey('business_fresh')), findsOneWidget);
    gate.complete(reply(pending!, [row('late-page')]));
    await frames(tester);
    expect(find.byKey(const ValueKey('business_fresh')), findsOneWidget);
    expect(find.byKey(const ValueKey('business_late-page')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Business map contact records one click and social links are not map events',
      (tester) async {
    final opened = <Uri>[];
    await mount(
        tester,
        BusinessAdDetailsPage(
            ad: BusinessAdData.fromJson(row('contact')),
            linkLauncher: (uri) async {
              opened.add(uri);
              return false;
            }));
    for (final label in [t('settings_show_on_map'), 'Instagram']) {
      await tester.scrollUntilVisible(find.text(label), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(label));
      await frames(tester);
    }
    final counters = analytics
        .where((r) => r.url.path.endsWith('/business-ads/events/counter'))
        .map((r) => jsonDecode(r.body))
        .where((p) => p['counter'] == 'clicks_count');
    expect(counters, hasLength(2));
    final events = analytics
        .where((r) => r.url.path.endsWith('/business-ads/events'))
        .map((r) => jsonDecode(r.body)['event_type']);
    expect(events.where((e) => e == 'map'), hasLength(1));
    expect(events.where((e) => e == 'click'), hasLength(2));
    expect(opened, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
