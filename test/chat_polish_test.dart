import 'package:motri_iq/l10n/app_delegates.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  'buyer_id': userId,
  'seller_id': 'other',
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
  var failRead = false, failSend = false, sends = 0;
  bool emptyMessages = false;
  String blockStatus = 'none';
  Map<String, dynamic>? submittedUserReport;
  var blockWrites = 0, blockDeletes = 0;
  Completer<void>? sendGate;
  Completer<void>? readGate;
  var authUser = userId;
  Uri? lastRead;
  final apiRequests = <http.Request>[];
  var messageReads = 0;
  Future<void> signIn(String id, String email) async {
    authUser = id;
    await Supabase.instance.client.auth
        .signInWithPassword(email: email, password: 'fixture-only');
    await backendAuthSession.login(email: email, password: 'fixture-only');
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final signature =
        base64Url.encode(List<int>.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          Object body = <String, dynamic>{};
          var status = 200;
          if (request.url.path == '/auth/v1/token') {
            final activePayload = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': authUser,
                  'role': 'authenticated',
                  'exp': DateTime.now()
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch ~/
                      1000
                })))
                .replaceAll('=', '');
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$activePayload.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': authUser,
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
    backendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async {
        Object body = <String, dynamic>{};
        if (request.url.path.endsWith('/auth/login')) {
          body = {
            'authenticated': true,
            'access_token': 'fixture-backend-access-token',
            'refresh_token': 'fixture-backend-refresh-token',
            'expires_in': 3600,
            'user': {
              'id': authUser,
              'email': 'fixture@example.com',
            },
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendAccessToken: () => backendAuthSession.accessToken,
      backendAccessTokenAsync: () => backendAuthSession.validAccessToken(),
      client: MockClient((request) async {
        Object data = <String, dynamic>{};
        var status = 200;
        final path = request.url.path;
        apiRequests.add(request);
        if (path.endsWith('/offers/conversations')) {
          data = {
            'data': [
              {
                ...offer,
                'car_offer_messages': [
                  {'body': 'Latest conversation message'}
                ],
              }
            ],
          };
        } else if (path.endsWith('/offers/${offer['id']}/messages')) {
          if (request.method == 'GET') {
            lastRead = request.url;
            messageReads++;
            await readGate?.future;
            if (failRead) {
              status = 400;
              data = {'message': 'Private database diagnostics'};
            } else {
              data = {
                'data': emptyMessages
                    ? <Map<String, dynamic>>[]
                    : [
                        {
                          'id': 'new',
                          'sender_id': authUser,
                          'body':
                              'My message with long text العربية کوردی and vehicle details that wrap safely.'
                        },
                        {
                          'id': 'old',
                          'sender_id': 'other',
                          'body': 'Seller response'
                        }
                      ]
              };
            }
          } else if (request.method == 'POST') {
            sends++;
            await sendGate?.future;
            if (failSend) {
              status = 400;
              data = {'message': 'Private send diagnostics'};
            } else {
              status = 201;
              data = {'data': <dynamic>[]};
            }
          }
        } else if (path.endsWith('/safety/blocks/other') &&
            request.method == 'GET') {
          data = {'blocked_by_me': blockStatus == 'blocked_by_me'};
        } else if (path.endsWith('/safety/blocks') &&
            request.method == 'POST') {
          blockWrites++;
          blockStatus = 'blocked_by_me';
          status = 201;
        } else if (path.endsWith('/safety/blocks/other') &&
            request.method == 'DELETE') {
          blockDeletes++;
          blockStatus = 'none';
        } else if (path.endsWith('/safety/reports') &&
            request.method == 'POST') {
          submittedUserReport = {
            ...jsonDecode(request.body) as Map<String, dynamic>,
            'reporter_id': backendAuthSession.user?.id,
          };
          status = 201;
          data = {
            'data': {'id': submittedUserReport!['id']}
          };
        }
        return http.Response(
          jsonEncode(data),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request,
        );
      }),
    );
  });
  setUp(() async {
    await signIn(userId, 'fixture@example.com');
    messageReads = 0;
    apiRequests.clear();
    emptyMessages = false;
    blockStatus = 'none';
    submittedUserReport = null;
    blockWrites = 0;
    blockDeletes = 0;
    failRead = false;
    failSend = false;
    sends = 0;
    sendGate = null;
    readGate = null;
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
  });
  tearDownAll(() async {
    await signOut();
    backendAuthSession.dispose();
    backendApi.close();
  });
  Future<void> mount(WidgetTester tester,
      {Brightness brightness = Brightness.light,
      double keyboard = 0,
      Widget page = const CarOfferChatPage(offer: offer)}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 640);
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
            data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.6),
                viewInsets: const bool.fromEnvironment('NATIVE_VIEWPORT')
                    ? MediaQuery.of(context).viewInsets
                    : EdgeInsets.only(bottom: keyboard)),
            child: child!),
        home: page));
    await frames(tester);
  }

  testWidgets(
      'Backend-authenticated user opens and sends a conversation without Supabase session',
      (tester) async {
    await tester.runAsync(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local),
    );
    expect(Supabase.instance.client.auth.currentUser, isNull);
    expect(backendAuthSession.user?.id, userId);

    await mount(tester, page: const MyMessagesPage());
    expect(find.text(offer['car_title'] as String), findsOneWidget);
    expect(find.text(t('login_required_first')), findsNothing);
    expect(
        apiRequests.any((request) =>
            request.url.path.endsWith('/offers/conversations') &&
            request.headers['authorization']?.startsWith('Bearer ') == true),
        isTrue);

    await tester.tap(find.text(offer['car_title'] as String));
    await frames(tester);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            (widget.data?.startsWith('My message') ?? false)),
        findsOneWidget);
    expect(find.text(t('login_required_first')), findsNothing);

    await tester.enterText(
        find.byType(TextField), 'Message from independent session');
    await tester.pump();
    final sendButton = find.ancestor(
      of: find.byIcon(Icons.send_rounded),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNotNull);
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    expect(sends, 1);
    expect(
        apiRequests.any((request) =>
            request.method == 'POST' &&
            request.url.path.endsWith('/offers/${offer['id']}/messages') &&
            request.headers['authorization']?.startsWith('Bearer ') == true),
        isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('state gap chat successful empty read', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    emptyMessages = true;
    await mount(tester);
    expect(find.text(t('chat_start')), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(t('chat_load_failed')), findsNothing);
    await currentTypographyCheckpoint(tester, 'GAP_CHAT_EMPTY');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('block requires confirmation and disables the chat',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip(t('chat_safety_options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('chat_block_user')));
    await tester.pumpAndSettle();
    expect(find.text(t('chat_block_confirm')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, t('chat_block_user')));
    await frames(tester);
    expect(blockWrites, 1);
    expect(find.text(t('chat_blocked_notice')), findsOneWidget);
    expect(find.byTooltip(t('chat_send')), findsNothing);
    await tester.tap(find.byTooltip(t('chat_safety_options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('chat_unblock_user')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, t('chat_unblock_user')));
    await frames(tester);
    expect(blockDeletes, 1);
    await tester.scrollUntilVisible(
      find.text('Seller response'),
      100,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Seller response'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('user report includes selected reason and details',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip(t('chat_safety_options')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t('chat_report_user')));
    await tester.pumpAndSettle();
    expect(find.text(t('ugc_report_user_title')), findsOneWidget);
    final details = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(details.last, 'Harassing messages');
    await tester.tap(find.text(t('report_submit')));
    await frames(tester);
    expect(submittedUserReport, isNotNull);
    expect(submittedUserReport!['reporter_id'], userId);
    expect(submittedUserReport!['reported_user_id'], 'other');
    expect(submittedUserReport!['offer_id'], 'offer-1');
    expect(submittedUserReport!['reason'], 'harassment');
    expect(submittedUserReport!['details'], 'Harassing messages');
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${locale.code} chat populated $brightness narrow large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, brightness: brightness);
        expect(tester.takeException(), isNull);
        expect(
            find.byWidgetPredicate((w) =>
                w is SelectableText &&
                (w.data?.startsWith('My message') ?? false)),
            findsOneWidget);
        final message = tester.widget<SelectableText>(find.byWidgetPredicate(
            (w) =>
                w is SelectableText &&
                (w.data?.startsWith('My message') ?? false)));
        expect(message.textDirection, TextDirection.ltr,
            reason: 'English punctuation follows the message language in RTL');
        expect(lastRead!.queryParameters['order'], 'created_at.desc.nullslast');
        expect(lastRead!.queryParameters['limit'], '200');
        final list = tester.widget<ListView>(find.byType(ListView));
        expect(list.reverse, isTrue);
        expect(find.byTooltip(t('chat_send')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'CHAT');
        if (const bool.fromEnvironment('UI_CHAT_REVIEW_HOLD') &&
            locale == AppLocale.en &&
            brightness == Brightness.dark) {
          debugPrint('UI_CHAT_REVIEW_READY');
          await Future<void>.delayed(const Duration(seconds: 15));
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
  testWidgets('initial delayed chat read shows loading before messages',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    readGate = Completer<void>();
    await mount(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t('chat_empty')), findsNothing);
    expect(find.text(t('chat_load_failed')), findsNothing);
    await currentTypographyCheckpoint(tester, 'CHAT_INITIAL_LOADING');
    readGate!.complete();
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
        find.byWidgetPredicate((w) =>
            w is SelectableText && (w.data?.startsWith('My message') ?? false)),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('chat error has localized retry and masks diagnostics',
      (tester) async {
    failRead = true;
    await mount(tester);
    expect(find.text(t('chat_load_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    failRead = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(
        find.byWidgetPredicate((w) =>
            w is SelectableText && (w.data?.startsWith('My message') ?? false)),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final locale in [AppLocale.ar, AppLocale.ku]) {
    testWidgets('${locale.code} chat composer remains above keyboard',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester,
          brightness:
              locale == AppLocale.ku ? Brightness.dark : Brightness.light,
          keyboard: 260);
      await tester.enterText(
          find.byType(TextField), 'A message about this vehicle');
      if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)));
      }
      await frames(tester);
      final keyboard = const bool.fromEnvironment('NATIVE_VIEWPORT')
          ? tester.view.viewInsets.bottom / tester.view.devicePixelRatio
          : 260.0;
      expect(keyboard, greaterThan(0));
      final send = find.byWidgetPredicate(
          (w) => w is IconButton && w.tooltip == t('chat_send'));
      expect(
          tester.getBottomRight(send).dy,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
                  keyboard));
      expect(tester.widget<IconButton>(send).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await currentTypographyCheckpoint(tester, 'CHAT_COMPOSER');
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('chat disables blank sends and keeps active send icon readable',
      (tester) async {
    await mount(tester);
    final send = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == t('chat_send'));
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '   ');
    await frames(tester);
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Hello');
    await frames(tester);
    final button = tester.widget<IconButton>(send);
    expect(button.onPressed, isNotNull);
    final foreground = (button.icon as Icon).color!;
    final background = Theme.of(tester.element(send)).colorScheme.primary;
    final a = foreground.computeLuminance(), b = background.computeLuminance();
    expect(((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
        greaterThanOrEqualTo(4.5));
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('failed send retains draft and duplicate send is disabled',
      (tester) async {
    failSend = true;
    sendGate = Completer<void>();
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Draft message');
    await tester.pump();
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == t('chat_send')))
            .onPressed,
        isNull);
    expect(sends, 1);
    sendGate!.complete();
    await frames(tester);
    expect(find.text(t('chat_send_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft message');
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('successful send preserves a newer draft', (tester) async {
    sendGate = Completer<void>();
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'First message');
    await tester.pump();
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    expect(sends, 1);
    await tester.enterText(find.byType(TextField), 'Next draft');
    sendGate!.complete();
    await frames(tester);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Next draft');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('send completion after closing chat avoids disposed controller',
      (tester) async {
    sendGate = Completer<void>();
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Leaving chat');
    await tester.pump();
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    expect(sends, 1);
    await tester.pumpWidget(const SizedBox());
    sendGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('polling retains existing messages while loading',
      (tester) async {
    await mount(tester);
    readGate = Completer<void>();
    await tester.pump(const Duration(seconds: 10));
    expect(
        find.byWidgetPredicate((w) =>
            w is SelectableText && (w.data?.startsWith('My message') ?? false)),
        findsOneWidget);
    readGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('chat logout clears rows and draft and stops polling',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Private draft');
    await tester.runAsync(signOut);
    await frames(tester);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(t('login_required_first')), findsOneWidget);
    final before = messageReads;
    await tester.pump(const Duration(seconds: 20));
    await frames(tester);
    expect(messageReads, before);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('chat late read after logout never restores private rows',
      (tester) async {
    readGate = Completer<void>();
    await mount(tester);
    await tester.runAsync(signOut);
    readGate!.complete();
    await frames(tester);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text(t('login_required_first')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('chat late send after logout cannot reload or track a response',
      (tester) async {
    sendGate = Completer<void>();
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Pending private message');
    await tester.pump();
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    final before = messageReads;
    await tester.runAsync(signOut);
    sendGate!.complete();
    await frames(tester);
    expect(messageReads, before);
    expect(
      apiRequests.any((request) =>
          request.url.path.endsWith('/seller_response_tracking')),
      isFalse,
    );
    expect(find.byType(TextField), findsNothing);
    expect(find.text(t('chat_send_failed')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'chat different account cannot inherit rows or draft; original account can reopen',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Original private draft');
    await tester.runAsync(() =>
        signIn('00000000-0000-4000-8000-000000000002', 'second@example.com'));
    await frames(tester);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
    final before = messageReads;
    await tester.pump(const Duration(seconds: 20));
    expect(messageReads, before);
    await tester.runAsync(() => signIn(userId, 'fixture@example.com'));
    await frames(tester);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    expect(find.byType(SelectableText), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('chat message sends do not call legacy response tracking',
      (tester) async {
    await mount(tester);
    await tester.enterText(find.byType(TextField), 'Message before logout');
    await tester.pump();
    await tester.tap(find.byTooltip(t('chat_send')));
    await frames(tester);
    expect(sends, 1);
    expect(
      apiRequests.any((request) =>
          request.url.path.endsWith('/seller_response_tracking')),
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code} chat draft direction preserves cursor and composition',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester);
      final input = find.byType(TextField);
      final controller = tester.widget<TextField>(input).controller!;
      for (final sample in [
        'Hello about this car',
        '\u0639\u0644\u064a',
        '\u0633\u06d5\u06cc\u0627\u0631\u06d5'
      ]) {
        final value = TextEditingValue(
            text: sample,
            selection: const TextSelection.collapsed(offset: 1),
            composing: const TextRange(start: 0, end: 2));
        controller.value = value;
        await frames(tester);
        expect(tester.widget<TextField>(input).textDirection,
            sample.startsWith('Hello') ? TextDirection.ltr : TextDirection.rtl);
        expect(controller.value, value,
            reason:
                'Direction updates must not commit an active IME composition or move the cursor');
      }
      controller.clear();
      await frames(tester);
      expect(tester.widget<TextField>(input).textDirection, locale.direction);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
