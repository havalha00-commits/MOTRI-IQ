import 'package:motri_iq/l10n/app_delegates.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/wallet/wallet_top_up_page.dart';

const userId = '00000000-0000-4000-8000-000000000001';
const txId = 'b1f6b1a2-c3d4-4e5f-8a9b-0c1d2e3f4a5b';
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

class _WalletBackendClient implements http.Client {
  final http.BaseClient _mock;
  _WalletBackendClient(this._mock);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _mock.send(request);
  @override
  void close() {}
  @override
  Future<http.Response> delete(Uri url,
          {Object? body, Encoding? encoding, Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<http.Response> head(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<http.Response> patch(Uri url,
          {Object? body, Encoding? encoding, Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<http.Response> post(Uri url,
          {Object? body, Encoding? encoding, Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<http.Response> put(Uri url,
          {Object? body, Encoding? encoding, Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<String> read(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> readBytes(Uri url, {Map<String, String>? headers}) =>
      throw UnimplementedError();
}

void main() {
  var settingsFail = false,
      configured = true,
      insertFail = false,
      pickerFail = false;
  var inserts = 0, uploads = 0, pickerCalls = 0;
  var uploadFail = false;
  Completer<void>? insertGate, pickerGate, uploadGate, settingsGate;
  Map<String, dynamic>? inserted;
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
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
          } else if (request.url.path.endsWith('wallet_settings')) {
            await settingsGate?.future;
            if (settingsFail) {
              status = 400;
              body = {'message': 'Private settings diagnostics'};
            } else {
              body = configured ? {'value': '1234 5678 9012 3456'} : null;
            }
          } else if (request.url.path.contains('/storage/v1/object/')) {
            uploads++;
            await uploadGate?.future;
            if (uploadFail) {
              status = 400;
              body = {'message': 'Private upload diagnostics'};
            } else {
              body = {'Key': request.url.path.split('/object/').last};
            }
          } else if (request.url.path.endsWith('wallet_transactions') &&
              request.method == 'POST') {
            inserts++;
            inserted =
                Map<String, dynamic>.from(jsonDecode(request.body) as Map);
            await insertGate?.future;
            if (insertFail) {
              status = 400;
              body = {'message': 'Private insert diagnostics'};
            }
          } else if (request.url.path.endsWith('app_admins')) {
            body = null;
          }
          return http.Response(jsonEncode(body), status,
              headers: {'content-type': 'application/json; charset=utf-8'},
              request: request);
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only');
    final backendMock = MockClient((request) async {
      Object? body;
      var status = 200;
      if (request.url.path.endsWith('wallet/topups') &&
          request.method == 'POST') {
        inserts++;
        inserted = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map<String, dynamic>);
        await insertGate?.future;
        if (insertFail) {
          status = 400;
          body = {'message': 'Private insert diagnostics'};
        } else {
          body = {'success': true, 'data': {'id': txId}};
        }
      } else {
        status = 404;
        body = {'error': 'not found'};
      }
      return http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json; charset=utf-8'},
          request: request);
    });
    backendApi = BackendApi(
      baseUrl: backendUrl,
      accessToken: () => supabase.auth.currentSession?.accessToken,
      client: _WalletBackendClient(backendMock),
    );
  });
  setUp(() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      await Supabase.instance.client.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only');
    }
    settingsFail = false;
    settingsGate = null;
    configured = true;
    insertFail = false;
    pickerFail = false;
    inserts = 0;
    uploads = 0;
    pickerCalls = 0;
    uploadFail = false;
    inserted = null;
    insertGate = null;
    pickerGate = null;
    uploadGate = null;
  });
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  Future<XFile?> pick() async {
    pickerCalls++;
    await pickerGate?.future;
    if (pickerFail) throw StateError('Private picker diagnostics');
    return XFile.fromData(png, name: 'receipt.png', mimeType: 'image/png');
  }

  Widget payment() => const SizedBox.shrink();
  Future<void> mount(WidgetTester tester, Widget page,
      {Brightness brightness = Brightness.light}) async {
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

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await frames(tester);
  }

  Finder submit() => find.byKey(const ValueKey('wallet_submit'));
  Future<void> receipt(WidgetTester tester) async {
    final button =
        find.widgetWithText(OutlinedButton, t('wallet_pick_receipt'));
    await reveal(tester, button);
    await tester.tap(button);
    await frames(tester);
  }

  testWidgets('state gap wallet delayed configuration', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    settingsGate = Completer<void>();
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await reveal(tester, find.text(t('ui_loading_title')));
    expect(find.text(t('wallet_account_not_set')), findsNothing);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    await currentTypographyCheckpoint(tester, 'GAP_WALLET_LOADING');
    settingsGate!.complete();
    await frames(tester);
    expect(find.text(t('ui_loading_title')), findsNothing);
    expect(find.text(t('wallet_account_not_set')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      for (final wallet in [true, false]) {
        testWidgets(
            '${locale.code} ${wallet ? 'wallet' : 'payment'} $brightness large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          await mount(
              tester, wallet ? WalletTopUpPage(receiptPicker: pick) : payment(),
              brightness: brightness);
          expect(tester.takeException(), isNull);
          if (wallet) {
            expect(find.byType(ChoiceChip), findsNWidgets(5));
            for (final entry in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList().asMap().entries) {
              final label = entry.value.label as Text;
              expect(label.textDirection, TextDirection.ltr);
              expect(label.data, formatIqd([5000, 10000, 25000, 50000, 100000][entry.key]));
            }
          } else {
            expect(find.textContaining('0770 123 4567'), findsNothing);
            expect(find.text(t('ui_manual_payment_steps')), findsOneWidget);
            final price = find.byWidgetPredicate((w) =>
                w is SelectableText &&
                w.data ==
                    '\u206625\u00a0USD\u2069\n\u206632,750\u00a0IQD\u2069');
            expect(price, findsOneWidget);
            expect(tester.widget<SelectableText>(price).textDirection,
                TextDirection.ltr);
          }
          await currentTypographyCheckpoint(
              tester, wallet ? 'WALLET' : 'PAYMENT');
          if (const bool.fromEnvironment('UI_WALLET_PAYMENT_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              brightness == Brightness.dark) {
            debugPrint(
                wallet ? 'UI_WALLET_REVIEW_READY' : 'UI_PAYMENT_REVIEW_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          await reveal(tester,
              wallet ? submit() : find.text(t('ui_payment_back_listings')));
          expect(tester.takeException(), isNull);
          await finish(tester);
        });
      }
    }
  }
  testWidgets('settings failure retries and missing configuration is distinct',
      (tester) async {
    settingsFail = true;
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('wallet_account_not_set')), findsNothing);
    settingsFail = false;
    configured = false;
    await reveal(tester, find.text(t('ui_retry')));
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('wallet_account_not_set')), findsOneWidget);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    await finish(tester);
  });
  testWidgets('amount and receipt validation avoid writes', (tester) async {
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await reveal(tester, submit());
    await tester.tap(submit());
    await frames(tester);
    expect(find.text(t('wallet_no_amount')), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(WalletTopUpPage)))
        .clearSnackBars();
    await frames(tester);
    final chip = find.byType(ChoiceChip).first;
    await reveal(tester, chip);
    await tester.tap(chip);
    await frames(tester);
    await reveal(tester, submit());
    await tester.tap(submit());
    await frames(tester);
    expect(
        find.descendant(
            of: find.byType(SnackBar),
            matching: find.text(t('wallet_pick_receipt'))),
        findsOneWidget);
    expect(uploads, 0);
    expect(inserts, 0);
    await finish(tester);
  });
  testWidgets('picker failure is localized and route closure is safe',
      (tester) async {
    pickerFail = true;
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await receipt(tester);
    expect(find.text(t('wallet_pick_image_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    ScaffoldMessenger.of(tester.element(find.byType(WalletTopUpPage)))
        .clearSnackBars();
    await frames(tester);
    pickerFail = false;
    pickerGate = Completer<void>();
    await receipt(tester);
    expect(pickerCalls, 2);
    await finish(tester);
    pickerGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('successful pending top-up prevents duplicate requests',
      (tester) async {
    insertGate = Completer<void>();
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await tester.tap(find.byType(ChoiceChip).first);
    await frames(tester);
    await receipt(tester);
    await reveal(tester, submit());
    await tester.tap(submit());
    await frames(tester);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNull);
    expect(inserts, 1);
    expect(uploads, 1);
    expect(inserted!['amount'], 5000);
    expect(inserted!['receipt_image_url'], startsWith('$userId/receipts/'));
    insertGate!.complete();
    await frames(tester);
    expect(find.text(t('wallet_submitted_success')), findsWidgets);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  for (final pending in ['picker', 'upload', 'insert']) {
    testWidgets('wallet ignores late $pending after session replacement', (tester) async {
      final gate = Completer<void>();
      if (pending == 'picker') pickerGate = gate;
      if (pending == 'upload') uploadGate = gate;
      if (pending == 'insert') insertGate = gate;
      await mount(tester, WalletTopUpPage(receiptPicker: pick));
      await tester.tap(find.byType(ChoiceChip).first);
      await frames(tester);
      await receipt(tester);
      if (pending != 'picker') {
        await reveal(tester, submit());
        await tester.tap(submit());
        await frames(tester);
        expect(uploads, 1);
        expect(inserts, pending == 'insert' ? 1 : 0);
      }
      await tester.runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      expect(find.text(t('login_not_logged_in')), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      // Even the same account returning is a new session, not the old draft.
      await tester.runAsync(() => supabase.auth.signInWithPassword(email: 'fixture@example.com', password: 'fixture-only')); 
      await frames(tester);
      gate.complete();
      await frames(tester);
      expect(find.text(t('wallet_submitted_success')), findsNothing);
      expect(tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).every((c) => !c.selected), isTrue);
      expect(find.byType(Image), findsNothing);
      expect(inserts, pending == 'insert' ? 1 : 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('failed top-up retains selected amount and receipt',
      (tester) async {
    insertFail = true;
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await tester.tap(find.byType(ChoiceChip).first);
    await frames(tester);
    await receipt(tester);
    await reveal(tester, submit());
    await tester.tap(submit());
    await frames(tester);
    expect(find.text(t('ui_wallet_submit_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    expect(tester.widget<ChoiceChip>(find.byType(ChoiceChip).first).selected,
        isTrue);
    expect(find.byType(Image), findsWidgets);
    await finish(tester);
  });
  testWidgets('payment support action opens existing support center',
      (tester) async {
    await mount(tester, payment());
    final support = find.widgetWithText(OutlinedButton, t('support_contact'));
    await reveal(tester, support);
    await tester.tap(support);
    await frames(tester);
    expect(find.byType(SupportCenterPage), findsOneWidget);
    await finish(tester);
  });
  testWidgets('receipt upload failure never creates a pending transaction',
      (tester) async {
    uploadFail = true;
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    await tester.tap(find.byType(ChoiceChip).first);
    await frames(tester);
    await receipt(tester);
    await reveal(tester, submit());
    await tester.tap(submit());
    await frames(tester);
    expect(uploads, 1);
    expect(inserts, 0);
    expect(find.text(t('ui_wallet_submit_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    expect(tester.widget<FilledButton>(submit()).onPressed, isNotNull);
    await finish(tester);
  });
  testWidgets('guest top-up shows sign-in state before payment instructions',
      (tester) async {
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await mount(tester, WalletTopUpPage(receiptPicker: pick));
    expect(find.text(t('login_not_logged_in')), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(inserts, 0);
    await finish(tester);
  });
}
