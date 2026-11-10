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

const userId = '00000000-0000-4000-8000-000000000001';
const offer = {
  'id': 'offer-1',
  'car_title': 'MOTRI automotive marketplace vehicle with a long model name'
};
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  var failRead = false, failNames = false;
  Completer<void>? readGate;
  Uri? conversationQuery;
  var messageRows = <Map<String, dynamic>>[];
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': userId,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final signature =
        base64Url.encode(List<int>.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          Object? body = [];
          var status = 200;
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': userId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
          } else if (request.url.path.endsWith('car_offers')) {
            conversationQuery = request.url;
            await readGate?.future;
            if (failRead) {
              status = 400;
              body = {'message': 'Private diagnostics'};
            } else {
              body = messageRows;
            }
          } else if (request.url.path.endsWith('seller_reviews')) {
            await readGate?.future;
            if (failRead) {
              status = 400;
              body = {'message': 'Private diagnostics'};
            } else {
              body = [
                {
                  'id': 'review-1',
                  'seller_id': 'seller-1',
                  'rating': 4,
                  'comment':
                      'A detailed review of the seller and the vehicle with a long comment that wraps safely.'
                }
              ];
            }
          } else if (request.url.path.endsWith('seller_showrooms')) {
            if (failNames) {
              status = 400;
              body = {'message': 'Private name diagnostics'};
            } else {
              body = [
                {
                  'seller_id': 'seller-1',
                  'showroom_name':
                      'A very long automotive showroom and seller display name that must not collide with the rating'
                }
              ];
            }
          }
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() {
    failRead = false;
    failNames = false;
    readGate = null;
    conversationQuery = null;
    messageRows = [
      {
        ...offer,
        'offer_price': 25000,
        'status': 'accepted',
        'car_offer_messages': [
          {
            'body': 'Latest message for the busy conversation',
            'created_at': '2026-10-21'
          }
        ]
      },
      {
        ...offer,
        'id': 'offer-2',
        'car_title': 'Second vehicle',
        'offer_price': 18000,
        'status': 'accepted',
        'car_offer_messages': [
          {
            'body': 'Latest message for the quiet conversation',
            'created_at': '2026-10-20'
          }
        ]
      }
    ];
  });
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  Widget host(Widget page, Brightness brightness) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: appLocale.locale,
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      theme: buildAppTheme(brightness),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.6)),
          child: ValueListenableBuilder<AppLocale>(
              valueListenable: appLocaleNotifier,
              builder: (context, locale, _) =>
                  AppStringsScope(locale: locale, child: child!))),
      home: page);
  Future<void> mount(WidgetTester tester, Widget page,
      {Brightness brightness = Brightness.light}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = brightness == Brightness.dark;
    await tester.pumpWidget(host(page, brightness));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      for (final reviews in [true, false]) {
        testWidgets(
            '${locale.code} ${reviews ? 'reviews' : 'conversations'} $brightness populated large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          await mount(
              tester, reviews ? const MyReviewsPage() : const MyMessagesPage(),
              brightness: brightness);
          expect(tester.takeException(), isNull);
          if (reviews) {
            expect(find.text('4.0/5'), findsOneWidget);
          } else {
            expect(find.text('Latest message for the busy conversation'),
                findsOneWidget);
            expect(
                find.text(t('ui_conversation_offer_amount')
                    .replaceAll('{amount}', '25,000')),
                findsOneWidget);
          }
          await currentTypographyCheckpoint(
              tester, reviews ? 'MY_REVIEWS' : 'MY_MESSAGES');
          if (const bool.fromEnvironment('UI_SELLER_ACTIVITY_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              brightness == Brightness.dark) {
            debugPrint(reviews
                ? 'UI_MY_REVIEWS_REVIEW_READY'
                : 'UI_MY_MESSAGES_REVIEW_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          await finish(tester);
        });
      }
    }
  }
  testWidgets('conversation query limits latest message per offer',
      (tester) async {
    await mount(tester, const MyMessagesPage());
    expect(conversationQuery!.queryParameters['car_offer_messages.limit'], '1');
    expect(conversationQuery!.queryParameters['car_offer_messages.order'],
        'created_at.desc.nullslast');
    expect(conversationQuery!.queryParameters['select'],
        contains('car_offer_messages(body,created_at,sender_id)'));
    expect(conversationQuery!.queryParameters['limit'], '50');
    await tester.scrollUntilVisible(
        find.text('Latest message for the quiet conversation'), 200,
        scrollable: find.byType(Scrollable).first);
    await frames(tester);
    expect(
        find.text('Latest message for the quiet conversation'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('conversation opens chat and refreshes on return',
      (tester) async {
    await mount(tester, const MyMessagesPage());
    await tester.tap(find.text('Latest message for the busy conversation'));
    await frames(tester);
    expect(find.byType(CarOfferChatPage), findsOneWidget);
    messageRows.first['car_offer_messages'] = [
      {'body': 'Updated preview after conversation'}
    ];
    await tester.tap(find.byType(BackButton));
    await frames(tester);
    expect(find.text('Updated preview after conversation'), findsOneWidget);
    await finish(tester);
  });
  for (final reviews in [true, false]) {
    testWidgets(
        '${reviews ? 'reviews' : 'conversations'} refresh waits and failed read retries',
        (tester) async {
      await mount(
          tester, reviews ? const MyReviewsPage() : const MyMessagesPage());
      readGate = Completer<void>();
      var completed = false;
      final refresh =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final pending = refresh.onRefresh().then((_) {
        completed = true;
      });
      await frames(tester);
      expect(completed, isFalse);
      failRead = true;
      readGate!.complete();
      await frames(tester);
      await pending;
      expect(completed, isTrue);
      expect(find.text(t('ui_load_error_title')), findsOneWidget);
      expect(find.textContaining('Private'), findsNothing);
      failRead = false;
      await tester.tap(find.text(t('ui_retry')));
      await frames(tester);
      expect(find.text(t('ui_load_error_title')), findsNothing);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('missing showroom name fallback updates with locale',
      (tester) async {
    failNames = true;
    appLocaleNotifier.value = AppLocale.ar;
    await mount(tester, const MyReviewsPage());
    expect(find.text(t('default_seller_name')), findsOneWidget);
    appLocaleNotifier.value = AppLocale.en;
    await frames(tester);
    expect(find.text(t('default_seller_name')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('conversation without messages shows first-message guidance',
      (tester) async {
    messageRows = [
      {...offer, 'status': 'accepted', 'car_offer_messages': []}
    ];
    await mount(tester, const MyMessagesPage());
    expect(find.text(t('chat_start')), findsOneWidget);
    await finish(tester);
  });
}
