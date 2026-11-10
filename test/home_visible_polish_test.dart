import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

void main() {
  var failBusiness = false;
  var failMore = false;
  var populated = false;
  final businessRequests = <Uri>[];
  final previousApi = backendApi;
  late BackendApi testApi;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final name in [
      'com.llfbandit.app_links/events',
      'com.llfbandit.app_links/messages'
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: MockClient((request) async {
        return http.Response('{}', 200, request: request);
      }),
    );
    testApi = BackendApi(
    baseUrl: 'https://backend.example.test',
    client: MockClient((request) async {
      final business = request.url.path.endsWith('/business-ads/active');
      if (business) {
        expect(request.headers.containsKey('authorization'), isFalse);
        businessRequests.add(request.url);
      }
      final offset =
          int.tryParse(request.url.queryParameters['offset'] ?? '0') ?? 0;
      final failed = business && (failBusiness || (failMore && offset > 0));
      final rows = business && populated
          ? List.generate(
              offset == 0 ? 20 : 1,
              (i) => {
                    'id': 'business-${offset + i}',
                    'user_id': 'seller',
                    'business_name': 'Business ${offset + i}',
                    'category': 'svc_parts',
                    'status': 'active',
                    'image_urls': <String>[],
                    'created_at': '2026-10-20T10:00:00Z',
                  })
          : <dynamic>[];
      return http.Response(
        jsonEncode(failed
            ? {'message': 'temporary failure', 'code': 'XX000'}
            : {'success': true, 'data': rows}),
        failed ? 500 : 200,
        request: request,
        headers: {'content-type': 'application/json'},
      );
    }),
    );
    backendApi = testApi;
  });
  tearDownAll(() {
    backendApi = previousApi;
    testApi.close();
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets('Home ${locale.code} dark=$dark scale=$scale',
            (tester) async {
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize = const Size(320, 740);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          var searches = 0;
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(body: SafeArea(
                child: HomeTab(onOpenSearch: () => searches++))),
          ));
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 2)));
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(find.text(t('home_search_hint')), findsOneWidget);
          for (final key in ['nav_cars', 'nav_market', 'ui_home_services']) {
            final label = find.text(t(key));
            final paragraph = tester.renderObject<RenderParagraph>(label);
            expect(paragraph.text.style!.fontFamily, 'MotriLatin');
            expect(paragraph.text.style!.fontFamilyFallback,
                [locale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans']);
            expect(paragraph.text.style!.letterSpacing, 0);
          }
          expect(find.text(t('ui_home_discover')), findsNothing);
          expect(tester.takeException(), isNull);
          await currentTypographyCheckpoint(
              tester, scale == 1 ? 'HOME' : 'HOME_LARGE');
          await tester.ensureVisible(find.text(t('home_search_hint')));
          await tester.pump();
          await tester.tap(find.text(t('home_search_hint')));
          expect(searches, 1);
          // Quick routes remain real destinations, including with stacked large text.
          await tester.scrollUntilVisible(find.text(t('ui_home_services')), 150,
              scrollable: find.byType(Scrollable).first);
          await tester.ensureVisible(find.text(t('ui_home_services')));
          await tester.pump();
          await tester.tap(find.text(t('ui_home_services')));
          for (var i = 0; i < 30; i++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 2)));
            await tester.pump(const Duration(milliseconds: 30));
          }
          expect(find.byType(BusinessAdsPage), findsOneWidget);
          final error = tester.takeException();
          expect(error, isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
      }
    }
  }
  testWidgets('business feed distinguishes failure from empty and retries',
      (tester) async {
    failBusiness = true;
    appLocaleNotifier.value = AppLocale.en;
    await tester.pumpWidget(MaterialApp(home: const BusinessAdsPage()));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('misc_no_business_ads')), findsNothing);
    failBusiness = false;
    await tester.tap(find.text(t('ui_retry')));
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(find.text(t('misc_no_business_ads')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('business pagination retains rows and retries the same offset',
      (tester) async {
    populated = true;
    failMore = true;
    await tester.pumpWidget(MaterialApp(home: const BusinessAdsPage()));
    Future<void> frames() async {
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)));
        await tester.pump(const Duration(milliseconds: 30));
      }
    }

    await frames();
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).last);
    for (var i = 0; i < 5; i++) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await frames();
    }
    final error = find.byKey(const ValueKey('business_more_error'));
    expect(error, findsOneWidget);
    final count = businessRequests.length;
    await frames();
    expect(businessRequests.length, count,
        reason: 'No automatic retry loop after failure');
    failMore = false;
    await tester.ensureVisible(
        find.descendant(of: error, matching: find.text(t('ui_retry'))));
    await tester
        .tap(find.descendant(of: error, matching: find.text(t('ui_retry'))));
    await frames();
    expect(businessRequests.last.queryParameters['offset'], '20');
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await frames();
    expect(find.byKey(const ValueKey('business_business-20')), findsOneWidget);
    expect(error, findsNothing);
    expect(tester.takeException(), isNull);
    populated = false;
  });
  test('business loader propagates failures and pages as a public request',
      () async {
    failBusiness = true;
    await expectLater(loadActiveBusinessAds(), throwsA(anything));
    failBusiness = false;
    await loadActiveBusinessAds(offset: 20, limit: 20);
    expect(businessRequests.last.path, '/api/business-ads/active');
    expect(businessRequests.last.queryParameters.containsKey('order'), isFalse);
    expect(businessRequests.last.queryParameters['offset'], '20');
    expect(businessRequests.last.queryParameters['limit'], '20');
  });
}
