import 'package:motri_iq/l10n/app_delegates.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const offer = {
  'id': 'offer-1',
  'car_title': 'MOTRI automotive marketplace vehicle with a long model name'
};

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async =>
      _values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  var failRead = false,
      failOpen = false,
      offerAvailable = true,
      patches = 0,
      reads = 0;
  Completer<void>? patchGate;
  Completer<void>? readGate;
  var rows = <Map<String, dynamic>>[];
  final offerRow = <String, dynamic>{
    ...offer,
    'status': 'accepted',
    'offer_price': 25000
  };
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
          }
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendAccessToken: () => backendAuthSession.accessToken,
      backendAccessTokenAsync: () => backendAuthSession.validAccessToken(),
      client: MockClient((request) async {
        Object? data = [];
        var status = 200;
        final path = request.url.path;
        if (path.endsWith('/activity/notifications') &&
            request.method == 'GET') {
          reads++;
          await readGate?.future;
          if (failRead) {
            status = 400;
            data = {'message': 'Private diagnostics'};
          } else {
            data = rows;
          }
        } else if (path.contains('/activity/notifications/') &&
            path.endsWith('/read') &&
            request.method == 'PATCH') {
          patches++;
          await patchGate?.future;
          if (failOpen) {
            status = 400;
            data = {'message': 'Private diagnostics'};
          } else {
            for (final row in rows) {
              row['read_at'] = '2026-10-21T00:00:00Z';
            }
            data = <String, dynamic>{};
          }
        } else if (path.endsWith('/offers/buyer') && request.method == 'GET') {
          data = [
            offerRow,
            {...offerRow, 'id': 'pending', 'status': 'pending'},
            {...offerRow, 'id': 'rejected', 'status': 'rejected'}
          ];
        } else if (path.endsWith('/offers/${offer['id']}') &&
            request.method == 'GET') {
          data = offerAvailable ? offerRow : null;
        }
        return http.Response(
          jsonEncode({
            'success': status >= 200 && status < 300,
            'data': data,
          }),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    backendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async {
        final body = request.url.path.endsWith('/auth/login')
            ? {
                'authenticated': true,
                'access_token': 'fixture-backend-access-token',
                'refresh_token': 'fixture-backend-refresh-token',
                'expires_in': 3600,
                'user': {
                  'id': userId,
                  'email': 'fixture@example.com',
                },
              }
            : <String, dynamic>{};
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    await backendAuthSession.login(
      email: 'fixture@example.com',
      password: 'fixture-only',
    );
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
  });
  setUp(() {
    failRead = false;
    failOpen = false;
    offerAvailable = true;
    patches = 0;
    reads = 0;
    patchGate = null;
    readGate = null;
    rows = [
      {
        'id': 'notice-1',
        'notification_type': 'new_message',
        'offer_id': 'offer-1',
        'title': 'A new message about your vehicle with a long title',
        'body':
            'The buyer would like more details about the vehicle and a suitable time to view it.',
        'read_at': null
      },
      {
        'id': 'notice-2',
        'notification_type': 'new_message',
        'offer_id': 'offer-1',
        'title': 'Read message',
        'body': 'Previous conversation update',
        'read_at': '2026-10-20'
      }
    ];
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
  });
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  Future<void> mount(WidgetTester tester, Widget page,
      {Brightness brightness = Brightness.light}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = brightness == Brightness.dark;
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        theme: buildAppTheme(brightness),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.6)),
            child: child!),
        home: page));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      for (final activity in [true, false]) {
        testWidgets(
            '${locale.code} ${activity ? 'activity' : 'sent offers'} $brightness populated large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          await mount(
              tester,
              activity
                  ? const ActivityNotificationsPage()
                  : const MySentOffersPage(),
              brightness: brightness);
          expect(tester.takeException(), isNull);
          if (activity) {
            expect(find.text(t('ui_notification_unread')), findsOneWidget);
            expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
          } else {
            expect(
                find.text(
                    t('ui_sent_offer_amount').replaceAll('{amount}', '25,000')),
                findsWidgets);
            expect(find.textContaining(t('offer_accepted')), findsWidgets);
            expect(find.textContaining('عرضك:'),
                locale == AppLocale.ar ? findsWidgets : findsNothing);
          }
          await currentTypographyCheckpoint(
              tester, activity ? 'ACTIVITY' : 'SENT_OFFERS');
          if (const bool.fromEnvironment('UI_ACTIVITY_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              brightness == Brightness.dark) {
            debugPrint(activity
                ? 'UI_ACTIVITY_REVIEW_READY'
                : 'UI_SENT_OFFERS_REVIEW_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          await finish(tester);
        });
      }
    }
  }
  testWidgets('accepted sent offer opens its conversation', (tester) async {
    await mount(tester, const MySentOffersPage());
    await tester.tap(find.text(t('chat_open')));
    await frames(tester);
    expect(find.byType(CarOfferChatPage), findsOneWidget);
    await finish(tester);
  });
  testWidgets('unread notification marks read once and opens accepted chat',
      (tester) async {
    patchGate = Completer<void>();
    await mount(tester, const ActivityNotificationsPage());
    final title = find.text(rows.first['title'] as String);
    await tester.tap(title);
    await frames(tester);
    await tester.tap(title);
    await frames(tester);
    expect(patches, 1);
    patchGate!.complete();
    await frames(tester);
    expect(find.byType(CarOfferChatPage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await frames(tester);
    expect(find.text(t('ui_notification_unread')), findsNothing);
    await finish(tester);
  });
  testWidgets('failed notification open keeps unread and allows retry',
      (tester) async {
    failOpen = true;
    await mount(tester, const ActivityNotificationsPage());
    await tester.tap(find.text(rows.first['title'] as String));
    await frames(tester);
    expect(find.text(t('alerts_open_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    expect(find.text(t('ui_notification_unread')), findsOneWidget);
    failOpen = false;
    await tester.tap(find.text(rows.first['title'] as String));
    await frames(tester);
    expect(find.byType(CarOfferChatPage), findsOneWidget);
    await finish(tester);
  });
  testWidgets('missing accepted offer gives localized feedback',
      (tester) async {
    offerAvailable = false;
    await mount(tester, const ActivityNotificationsPage());
    await tester.tap(find.text(rows.first['title'] as String));
    await frames(tester);
    expect(find.text(t('ui_conversation_unavailable')), findsOneWidget);
    expect(find.byType(CarOfferChatPage), findsNothing);
    await finish(tester);
  });
  testWidgets('activity refresh waits for read and failed refresh recovers',
      (tester) async {
    await mount(tester, const ActivityNotificationsPage());
    readGate = Completer<void>();
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final before = reads;
    var completed = false;
    final pending = refresh.onRefresh().then((_) {
      completed = true;
    });
    await frames(tester);
    expect(completed, isFalse);
    expect(reads, greaterThan(before));
    failRead = true;
    readGate!.complete();
    await frames(tester);
    await pending;
    expect(completed, isTrue);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    failRead = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('ui_notification_unread')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
