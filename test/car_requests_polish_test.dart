import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/auth/auth_capabilities.dart';
import 'package:motri_iq/ui/car_request_editor_dialog.dart';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};

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
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final requests = <Uri>[];
  const newest = 'unused';
  var failRead = false, failWrite = false, noop = false, duplicate = false;
  var row = <String, dynamic>{};
  bool lostAck = false;
  final committedIds = <String>{};
  var writes = <Map<String, dynamic>>[];
  Completer<void>? gate, initialReadGate;
  bool emptyRows = false;
  late BackendApi oldBackendApi;
  late BackendApi testBackendApi;
  late BackendAuthSession oldBackendAuthSession;
  late BackendAuthSession testBackendAuthSession;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    oldBackendApi = backendApi;
    oldBackendAuthSession = backendAuthSession;
    const uid = '00000000-0000-4000-8000-000000000001';
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': uid,
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
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
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
            };
          }
          return http.Response(jsonEncode(body), 200,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
    testBackendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'authenticated': true,
              'access_token': 'fixture-access-token',
              'refresh_token': 'fixture-refresh-token',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'email': 'fixture@example.com',
                'is_admin': false,
              },
            }),
            200,
            request: request,
          )),
    );
    await testBackendAuthSession.login(
      email: 'fixture@example.com',
      password: 'fixture-only',
    );
    backendAuthSession = testBackendAuthSession;
    testBackendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => supabase.auth.currentSession?.accessToken,
      backendAccessTokenAsync: testBackendAuthSession.validAccessToken,
      backendAccessToken: () => testBackendAuthSession.accessToken,
      client: MockClient((request) async {
        requests.add(request.url);
        final path = request.url.path;
        if (request.method == 'GET' &&
            (path.endsWith('/requests') || path.endsWith('/requests/mine'))) {
          await initialReadGate?.future;
          if (failRead) {
            return http.Response(
              '{"message":"private diagnostic"}',
              500,
              request: request,
            );
          }
          final isMine = path.endsWith('/requests/mine');
          final rows = emptyRows ||
                  isMine &&
                      row['buyer_id'] != '00000000-0000-4000-8000-000000000001'
              ? <Map<String, dynamic>>[]
              : [row];
          return http.Response(
            jsonEncode({'success': true, 'data': rows}),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (request.method == 'POST' || request.method == 'PATCH') {
          final isOffer = path.contains('/offers');
          final payload = request.body.isEmpty
              ? <String, dynamic>{}
              : Map<String, dynamic>.from(jsonDecode(request.body));
          writes.add(payload);
          await gate?.future;
          if (duplicate && isOffer) {
            (row['car_request_offers'] as List).add({
              'id': 'existing-offer',
              'status': 'pending',
              'seller_id': '00000000-0000-4000-8000-000000000001',
              ...payload,
            });
            return http.Response(
              '{"code":"23505","message":"private diagnostic"}',
              409,
              request: request,
            );
          }
          if (failWrite) {
            return http.Response(
              '{"message":"private diagnostic"}',
              500,
              request: request,
            );
          }
          if (request.method == 'POST' &&
              !isOffer &&
              committedIds.contains(payload['id'])) {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'id': payload['id']},
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (noop) {
            return http.Response(
              jsonEncode({'success': true, 'data': <dynamic>[]}),
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.method == 'POST' && isOffer) {
            (row['car_request_offers'] as List).add({
              'id': 'new-offer',
              'status': 'pending',
              'seller_id': '00000000-0000-4000-8000-000000000001',
              ...payload,
            });
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'id': 'new-offer'},
              }),
              201,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (request.method == 'POST') {
            row = {
              'id': payload['id'],
              'status': 'open',
              'car_request_offers': <Map<String, dynamic>>[],
              ...payload,
            };
            committedIds.add(payload['id'] as String);
            return http.Response(
              jsonEncode({
                'success': true,
                'data': lostAck ? <dynamic>[] : {'id': payload['id']},
              }),
              201,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final status = path.endsWith('/close')
              ? 'closed'
              : payload['status']?.toString() ?? 'closed';
          if (path.endsWith('/close')) {
            row['status'] = status;
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'id': row['id'], 'status': status},
              }),
              200,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          final offerId = path.split('/').last;
          final offer = (row['car_request_offers'] as List)
              .cast<Map<String, dynamic>>()
              .firstWhere((item) => item['id'] == offerId);
          offer['status'] = status;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'id': offerId, 'status': status},
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"error":"not found"}', 404, request: request);
      }),
    );
    backendApi = testBackendApi;
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only');
    }
    if (backendAuthSession.user == null) {
      await backendAuthSession.login(
        email: 'fixture@example.com',
        password: 'fixture-only',
      );
    }
    requests.clear();
    committedIds.clear();
    lostAck = false;
    failRead = failWrite = noop = duplicate = false;
    writes = [];
    gate = null;
    initialReadGate = null;
    emptyRows = false;
    row = {
      'id': 'request-1',
      'buyer_id': '00000000-0000-4000-8000-000000000001',
      'brand': 'Toyota Land Cruiser',
      'model': 'Platinum with a long model description',
      'max_price': 25000,
      'year_from': 2020,
      'year_to': 2026,
      'province': 'A long province name',
      'details': 'A detailed buyer request with long specifications to wrap',
      'status': 'open',
      'car_request_offers': <Map<String, dynamic>>[
        {
          'id': 'offer-1',
          'seller_id': 'seller-1',
          'vehicle': 'A long available vehicle description',
          'offer_price': 24000,
          'message': 'A detailed seller offer message',
          'status': 'pending'
        }
      ]
    };
    SharedPreferences.setMockInitialValues({
      'search_history': [newest, 'Older query', 'Older query', '']
    });
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
    darkModeNotifier.value = ThemeMode.light;
  });
  tearDownAll(() async {
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
    backendApi = oldBackendApi;
    backendAuthSession = oldBackendAuthSession;
    testBackendApi.close();
    testBackendAuthSession.dispose();
  });
  Future<void> mount(WidgetTester tester, Widget page,
      {bool dark = false}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = dark;
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => AppStringsScope(
                locale: locale,
                child: AuthCapabilitiesScope(
                    loader: () async => const AuthCapabilitiesResult.ready(
                        AuthCapabilities(
                            phoneOtpEnabled: true, emailEnabled: true)),
                    child: MediaQuery(
                        data: MediaQuery.of(context)
                            .copyWith(textScaler: const TextScaler.linear(1.6)),
                        child: child!))),
            home: page)));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  Future<void> tapAction(WidgetTester tester, String key) async {
    final finder = find.text(t(key));
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await frames(tester);
  }

  Future<void> input(WidgetTester tester, String key, String value) async {
    final finder = find.byKey(ValueKey('request_$key'));
    await Scrollable.ensureVisible(tester.element(finder), alignment: .5);
    await tester.pumpAndSettle();
    await tester.enterText(finder, value);
    await tester.pump();
  }

  Future<void> editor(WidgetTester tester, {bool offer = false}) async {
    if (offer) row['buyer_id'] = 'other-buyer';
    await mount(tester, const CarRequestsPage());
    await tapAction(
        tester, offer ? 'req_offer_for_your_car' : 'misc_request_cta');
    expect(find.byType(CarRequestEditorDialog), findsOneWidget);
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text(t('ui_business_confirm')));
    await frames(tester);
  }

  testWidgets('state gap requests delayed loading then empty', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    initialReadGate = Completer<void>();
    emptyRows = true;
    await mount(tester, const CarRequestsPage());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t('account_requests_none')), findsNothing);
    await currentTypographyCheckpoint(tester, 'GAP_REQUEST_LOADING');
    initialReadGate!.complete();
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text(t('account_requests_none')), findsOneWidget);
    expect(find.byType(RefreshIndicator), findsOneWidget);
    await currentTypographyCheckpoint(tester, 'GAP_REQUEST_EMPTY');
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final surface in ['cards', 'request', 'offer', 'decision']) {
        testWidgets('$locale requests $surface dark=$dark large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          if (surface == 'offer') row['buyer_id'] = 'other-buyer';
          await mount(tester, const CarRequestsPage(), dark: dark);
          if (surface == 'cards') {
            await Scrollable.ensureVisible(
                tester.element(find.text(t('offer_accept'))));
            await tester.pumpAndSettle();
            await tester.drag(find.byType(ListView), const Offset(0, 800));
            await tester.pumpAndSettle();
          } else if (surface == 'decision') {
            await tapAction(tester, 'offer_accept');
            expect(writes, isEmpty);
            expect(find.byType(LinearProgressIndicator), findsNothing);
          } else {
            await tapAction(
                tester,
                surface == 'offer'
                    ? 'req_offer_for_your_car'
                    : 'misc_request_cta');
            await input(tester, 'name', 'Toyota Land Cruiser');
            FocusManager.instance.primaryFocus?.unfocus();
            await frames(tester);
            final nameField = find.byKey(const ValueKey('request_name'));
            final controller = tester.widget<TextField>(nameField).controller!;
            const latin = TextEditingValue(
                text: 'Toyota Land Cruiser',
                selection: TextSelection(baseOffset: 1, extentOffset: 5),
                composing: TextRange(start: 0, end: 6));
            controller.value = latin;
            await frames(tester);
            expect(tester.widget<TextField>(nameField).textDirection,
                TextDirection.ltr);
            expect(controller.value, latin);
            controller.text = 'تويوتا';
            await frames(tester);
            expect(tester.widget<TextField>(nameField).textDirection,
                TextDirection.rtl);
            controller.text = latin.text;
            await frames(tester);
            await input(tester, 'price', '٢٥٬٠٠٠');
            await Scrollable.ensureVisible(
                tester.element(find.byKey(const ValueKey('request_name'))));
            await tester.pumpAndSettle();
          }
          FocusManager.instance.primaryFocus?.unfocus();
          if (surface == 'decision') {
            await frames(tester);
          } else {
            await tester.pumpAndSettle();
          }
          if (surface != 'cards' && surface != 'decision') {
            final outer = tester.state<ScrollableState>(find
                .descendant(
                    of: find.byType(AlertDialog),
                    matching: find.byType(Scrollable))
                .first);
            outer.position.jumpTo(0);
            await tester.pumpAndSettle();
          }
          expect(tester.takeException(), isNull);
          await currentTypographyCheckpoint(
              tester, 'REQUESTS_${surface.toUpperCase()}');
          if (locale == AppLocale.en &&
              dark &&
              const bool.fromEnvironment('UI_REQUESTS_REVIEW_HOLD')) {
            debugPrint('UI_REQUESTS_${surface.toUpperCase()}_READY');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 20)));
          }
          await finish(tester);
        });
      }
    }
  }
  testWidgets(
      'request validates years finite prices and keeps draft on locale change',
      (tester) async {
    await editor(tester);
    await input(tester, 'name', 'Toyota');
    await input(tester, 'price', 'NaN');
    await tapAction(tester, 'req_publish');
    expect(writes, isEmpty);
    await input(tester, 'price', '٢٥٬٠٠٠');
    await input(tester, 'from', 'bad');
    await tapAction(tester, 'req_publish');
    expect(find.text(t('ui_request_year_invalid')), findsOneWidget);
    await input(tester, 'from', '٢٠٢٦');
    await input(tester, 'to', '۲۰۲۰');
    await tapAction(tester, 'req_publish');
    expect(find.text(t('req_year_range_hint')), findsOneWidget);
    appLocaleNotifier.value = AppLocale.en;
    await frames(tester);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('request_name')))
            .textDirection,
        TextDirection.ltr);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('request_name')))
            .controller!
            .text,
        'Toyota');
    await input(tester, 'from', '٢٠٢٠');
    await input(tester, 'to', '۲۰۲۶');
    await tapAction(tester, 'req_publish');
    expect(writes.single['max_price'], 25000);
    expect(writes.single['year_from'], 2020);
    expect(writes.single['year_to'], 2026);
    expect(find.byType(CarRequestEditorDialog), findsNothing);
    await finish(tester);
  });
  for (final failed in [false, true]) {
    testWidgets('publish failed/noop=$failed retains draft and retries',
        (tester) async {
      failWrite = !failed;
      noop = failed;
      await editor(tester);
      await input(tester, 'name', 'Toyota');
      await input(tester, 'price', '25000');
      await tapAction(tester, 'req_publish');
      expect(find.text(t('req_publish_failed')), findsOneWidget);
      expect(find.textContaining('private diagnostic'), findsNothing);
      expect(
          tester
              .widget<TextField>(find.byKey(const ValueKey('request_name')))
              .controller!
              .text,
          'Toyota');
      failWrite = noop = false;
      await tapAction(tester, 'req_publish');
      expect(find.byType(CarRequestEditorDialog), findsNothing);
      await finish(tester);
    });
  }
  testWidgets('offer validates and sends localized price to correct parties',
      (tester) async {
    await editor(tester, offer: true);
    await tapAction(tester, 'req_send_offer');
    expect(writes, isEmpty);
    await input(tester, 'name', 'Camry');
    await input(tester, 'price', '۲۴٬۵۰۰٫۵');
    await tapAction(tester, 'req_send_offer');
    expect(writes.single['offer_price'], 24500.5);
    expect(writes.single.containsKey('buyer_id'), isFalse);
    expect(writes.single.containsKey('seller_id'), isFalse);
    expect(
        requests
            .lastWhere((u) => u.path.endsWith('/requests/request-1/offers'))
            .path,
        endsWith('/requests/request-1/offers'));
    expect(find.byType(CarRequestEditorDialog), findsNothing);
    await finish(tester);
  });
  testWidgets('duplicate offer shows translated feedback without success',
      (tester) async {
    duplicate = true;
    await editor(tester, offer: true);
    await input(tester, 'name', 'Camry');
    await input(tester, 'price', '24000');
    await tapAction(tester, 'req_send_offer');
    expect(find.text(t('req_offer_sent')), findsOneWidget);
    expect(find.byType(CarRequestEditorDialog), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    await tapAction(tester, 'common_cancel');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, t('req_offer_sent')))
            .onPressed,
        isNull);
    await finish(tester);
  });
  testWidgets(
      'pending submission guards taps and blocks dismiss until completed',
      (tester) async {
    gate = Completer<void>();
    await editor(tester);
    await input(tester, 'name', 'Toyota');
    await input(tester, 'price', '25000');
    await tapAction(tester, 'req_publish');
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, t('req_publish')))
            .onPressed,
        isNull);
    await tester.binding.handlePopRoute();
    await frames(tester);
    expect(find.byType(CarRequestEditorDialog), findsOneWidget);
    expect(writes.length, 1);
    gate!.complete();
    await frames(tester);
    expect(find.byType(CarRequestEditorDialog), findsNothing);
    await finish(tester);
  });
  testWidgets('cancel and dispose input routes cleanly', (tester) async {
    await editor(tester);
    await input(tester, 'name', 'Toyota');
    await tapAction(tester, 'common_cancel');
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final status in ['accepted', 'rejected', 'closed']) {
    testWidgets('owner confirmed $status decision is scoped and acknowledged',
        (tester) async {
      await mount(tester, const CarRequestsPage());
      await tapAction(
          tester,
          status == 'closed'
              ? 'req_close_request'
              : status == 'accepted'
                  ? 'offer_accept'
                  : 'offer_reject');
      expect(writes, isEmpty);
      await confirm(tester);
      final uri = requests.lastWhere((u) => status == 'closed'
          ? u.path.endsWith('/requests/request-1/close')
          : u.path.endsWith('/requests/request-1/offers/offer-1'));
      if (status == 'closed') {
        expect(uri.path, endsWith('/requests/request-1/close'));
        expect(writes.single, isEmpty);
      } else {
        expect(uri.path, endsWith('/requests/request-1/offers/offer-1'));
        expect(writes.single['status'], status);
      }
      expect(find.text(t('ui_request_updated')), findsOneWidget);
      await finish(tester);
    });
  }
  testWidgets('failed or noop decision does not claim success', (tester) async {
    noop = true;
    await mount(tester, const CarRequestsPage());
    await tapAction(tester, 'offer_accept');
    await confirm(tester);
    expect(find.text(t('ui_request_decision_failed')), findsOneWidget);
    expect(find.text(t('ui_request_updated')), findsNothing);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('${locale.code} request chip typography dark=$dark',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester, const CarRequestsPage(), dark: dark);
        final open = find.widgetWithText(ChoiceChip, t('ui_requests_open'));
        final mine = find.widgetWithText(ChoiceChip, t('my_requests'));
        expect(tester.widget<ChoiceChip>(open).selected, isTrue);
        expect(tester.widget<ChoiceChip>(mine).selected, isFalse);
        final theme = Theme.of(tester.element(open)).chipTheme;
        expect(theme.labelStyle?.fontFamily, 'MotriLatin');
        expect(theme.labelStyle?.fontFamilyFallback,
            [locale == AppLocale.ku ? 'MotriKurdish' : 'MotriSans']);
        await currentTypographyCheckpoint(tester, 'REQUEST_TABS_OPEN');
        await tester.tap(mine);
        await frames(tester);
        expect(tester.widget<ChoiceChip>(mine).selected, isTrue);
        expect(requests.any((u) => u.path.endsWith('/requests/mine')), isTrue);
        await currentTypographyCheckpoint(tester, 'REQUEST_TABS_MINE');
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  }
  testWidgets('read retry and mine filter preserve error privacy',
      (tester) async {
    failRead = true;
    await mount(tester, const CarRequestsPage());
    expect(find.textContaining('private diagnostic'), findsNothing);
    failRead = false;
    await tapAction(tester, 'ui_retry');
    await frames(tester);
    await tapAction(tester, 'my_requests');
    await frames(tester);
    expect(requests.any((u) => u.path.endsWith('/requests/mine')), isTrue);
    await finish(tester);
  });
  testWidgets('cancelling close performs no update', (tester) async {
    await mount(tester, const CarRequestsPage());
    await tapAction(tester, 'req_close_request');
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(writes, isEmpty);
    await finish(tester);
  });
  testWidgets('disposing a submitting editor does not use released controllers',
      (tester) async {
    gate = Completer<void>();
    await editor(tester, offer: true);
    await input(tester, 'name', 'Camry');
    await input(tester, 'price', '24000');
    await tapAction(tester, 'req_send_offer');
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('guest publishing and offering show login guidance',
      (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    row['buyer_id'] = 'other-buyer';
    await mount(tester, const CarRequestsPage());
    await tapAction(tester, 'misc_request_cta');
    expect(find.text(t('req_login_publish')), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(CarRequestsPage)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();
    await tapAction(tester, 'req_offer_for_your_car');
    expect(find.text(t('req_login_offer')), findsOneWidget);
    expect(writes, isEmpty);
    await finish(tester);
  });
  testWidgets(
      'lost request acknowledgement retries same draft and reconciles committed row',
      (tester) async {
    lostAck = true;
    await editor(tester);
    await input(tester, 'name', 'Toyota');
    await input(tester, 'price', '25000');
    await tapAction(tester, 'req_publish');
    expect(find.text(t('req_publish_failed')), findsOneWidget);
    expect(committedIds.length, 1);
    final id = writes.single['id'];
    lostAck = false;
    await tapAction(tester, 'req_publish');
    expect(writes.length, 2);
    expect(writes.last['id'], id);
    expect(committedIds.length, 1);
    expect(find.byType(CarRequestEditorDialog), findsNothing);
    expect(requests.any((u) => u.path.endsWith('/requests/mine')), isTrue);
    await finish(tester);
  });
  for (final offer in [false, true]) {
    testWidgets(
        'account loss during request submission offer=$offer retains editor without success',
        (tester) async {
      gate = Completer<void>();
      await editor(tester, offer: offer);
      await input(tester, 'name', 'Toyota');
      await input(tester, 'price', '25000');
      await tapAction(tester, offer ? 'req_send_offer' : 'req_publish');
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      gate!.complete();
      await frames(tester);
      expect(find.byType(CarRequestEditorDialog), findsOneWidget);
      expect(find.text(t('ui_business_session_changed')), findsOneWidget);
      expect(find.text(t(offer ? 'req_offer_sent_to_you' : 'req_sent')),
          findsNothing);
      await finish(tester);
      await tester.runAsync(() => supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only'));
    });
  }
  testWidgets('account loss while confirming a decision prevents update',
      (tester) async {
    await mount(tester, const CarRequestsPage());
    await tapAction(tester, 'offer_accept');
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await confirm(tester);
    expect(writes, isEmpty);
    expect(find.text(t('ui_request_updated')), findsNothing);
    await finish(tester);
    await tester.runAsync(() => supabase.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only'));
  });
  for (final locale in AppLocale.values) {
    testWidgets(
        'changed draft after a lost acknowledgement ${locale.code} cannot confirm outdated saved fields',
        (tester) async {
      lostAck = true;
      appLocaleNotifier.value = locale;
      await mount(tester, const CarRequestsPage(),
          dark: locale == AppLocale.ku);
      await tapAction(tester, 'misc_request_cta');
      await input(tester, 'name', 'Toyota');
      await input(tester, 'price', '25000');
      await tapAction(tester, 'req_publish');
      await input(tester, 'price', '30000');
      lostAck = false;
      await tapAction(tester, 'req_publish');
      expect(committedIds.length, 1);
      expect(writes, hasLength(1));
      expect(row['max_price'], 25000);
      expect(find.text(t('ui_request_already_saved')).hitTestable(),
          findsOneWidget);
      await currentTypographyCheckpoint(tester, 'REQUEST_RETRY');
      expect(find.byType(CarRequestEditorDialog), findsOneWidget);
      expect(find.text(t('req_sent')), findsNothing);
      await finish(tester);
    });
  }
  testWidgets(
      'request prices have primary USD and secondary IQD hierarchy with content direction',
      (tester) async {
    await mount(tester, const CarRequestsPage());
    final usd = tester.widget<Text>(find.text(formatUsd(25000)));
    final iqd =
        tester.widget<Text>(find.text(formatIqd((25000 * iqdPerUsd).round())));
    expect(usd.style!.fontSize!, greaterThan(iqd.style!.fontSize!));
    expect(
        tester
            .widget<Text>(find.text(
                'Toyota Land Cruiser Platinum with a long model description'))
            .textDirection,
        TextDirection.ltr);
    expect(
        tester.widget<Text>(find.text(row['details'] as String)).textDirection,
        TextDirection.ltr);
    await finish(tester);
  });
  testWidgets(
      'decision progress starts only after confirmation and ends with acknowledgement',
      (tester) async {
    await mount(tester, const CarRequestsPage());
    await tapAction(tester, 'offer_accept');
    expect(find.byType(LinearProgressIndicator), findsNothing);
    gate = Completer<void>();
    await confirm(tester);
    expect(writes.length, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate!.complete();
    await frames(tester);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text(t('ui_request_updated')), findsOneWidget);
    await finish(tester);
  });
}
