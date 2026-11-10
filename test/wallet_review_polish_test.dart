import 'package:motri_iq/l10n/app_delegates.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/wallet/wallet_admin_review_page.dart';

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
  var admin = true, accessFails = false, listFails = false, namesFail = false;
  var mode = 'success', decisions = 0, receiptRequests = 0;
  Completer<void>? decisionGate, readGate, accessGate, receiptGate;
  var walletReads = 0, profileReads = 0;
  var rows = <Map<String, dynamic>>[];
  Uri? walletQuery;
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
          } else if (request.url.path.endsWith('app_admins')) {
            await accessGate?.future;
            if (accessFails) {
              status = 400;
              body = {'message': 'Private access diagnostics'};
            } else {
              body = admin ? {'user_id': userId} : null;
            }
          } else if (request.url.path.endsWith('wallet_transactions')) {
            walletReads++;
            walletQuery = request.url;
            await readGate?.future;
            if (listFails) {
              status = 400;
              body = {'message': 'Private list diagnostics'};
            } else {
              body = rows;
            }
          } else if (request.url.path.endsWith('profiles')) {
            profileReads++;
            if (namesFail) {
              status = 400;
              body = {'message': 'Private profile diagnostics'};
            } else {
              body = [
                {
                  'id': 'owner-1',
                  'full_name':
                      'A very long wallet requester and automotive business owner name that must wrap safely'
                }
              ];
            }
          } else if (request.url.path.endsWith('admin_wallet_decide')) {
            decisions++;
            await decisionGate?.future;
            final params = jsonDecode(request.body) as Map;
            if (mode == 'success') {
              rows.removeWhere((row) => row['id'] == params['p_id']);
              body = {'ok': true, 'status': params['p_status']};
            } else if (mode == 'already_decided') {
              rows.removeWhere((row) => row['id'] == params['p_id']);
              body = {
                'ok': false,
                'reason': 'already_decided',
                'status': 'confirmed'
              };
            } else if (mode == 'wrong_status') {
              body = {'ok': true, 'status': 'rejected'};
            } else if (mode == 'exception') {
              status = 400;
              body = {'message': 'Private decision diagnostics'};
            } else {
              body = {'ok': false, 'reason': 'fixture_failure'};
            }
          } else if (request.url.path.contains('/storage/v1/object/sign/')) {
            receiptRequests++;
            await receiptGate?.future;
            status = 400;
            body = {'message': 'Private receipt diagnostics'};
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
      if (request.url.path.endsWith('wallet/decide') &&
          request.method == 'POST') {
        decisions++;
        await decisionGate?.future;
        final params = jsonDecode(request.body) as Map;
        if (mode == 'success') {
          rows.removeWhere((row) => row['id'] == params['id']);
          body = {'ok': true, 'status': params['status']};
        } else if (mode == 'already_decided') {
          rows.removeWhere((row) => row['id'] == params['id']);
          body = {
            'ok': false,
            'reason': 'already_decided',
            'status': 'confirmed'
          };
        } else if (mode == 'wrong_status') {
          body = {'ok': true, 'status': 'rejected'};
        } else if (mode == 'exception') {
          status = 400;
          body = {'message': 'Private decision diagnostics'};
        } else {
          body = {'ok': false, 'reason': 'fixture_failure'};
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
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture-only');
    }
    admin = true;
    accessFails = false;
    listFails = false;
    namesFail = false;
    mode = 'success';
    decisions = 0;
    receiptRequests = 0;
    decisionGate = null;
    readGate = accessGate = receiptGate = null;
    walletReads = profileReads = 0;
    walletQuery = null;
    rows = [
      {
        'id': 'tx-1',
        'user_id': 'owner-1',
        'amount': 100000,
        'payment_method': 'kcard',
        'receipt_image_url': 'owner-1/receipts/proof.jpg',
        'created_at': '2026-10-21T00:00:00Z',
        'status': 'pending'
      },
      {
        'id': 'tx-2',
        'user_id': 'owner-2',
        'amount': 5000,
        'payment_method': 'kcard',
        'receipt_image_url': null,
        'created_at': '2026-10-20T00:00:00Z',
        'status': 'pending'
      }
    ];
  });
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  Future<void> mount(WidgetTester tester,
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
        home: const WalletAdminReviewPage()));
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

  Future<void> openDecision(WidgetTester tester, {bool approve = true}) async {
    final button = find
        .widgetWithText(approve ? FilledButton : OutlinedButton,
            t(approve ? 'wallet_approve' : 'wallet_reject'))
        .first;
    await reveal(tester, button);
    await tester.tap(button);
    await frames(tester);
  }

  Future<void> confirm(WidgetTester tester, {bool approve = true}) async {
    final button = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(
            FilledButton, t(approve ? 'wallet_approve' : 'wallet_reject')));
    await tester.tap(button);
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          '${locale.code} wallet review dark=$dark populated large text',
          (tester) async {
        appLocaleNotifier.value = locale;
        await mount(tester,
            brightness: dark ? Brightness.dark : Brightness.light);
        expect(tester.takeException(), isNull);
        expect(find.text(formatIqd(100000)), findsOneWidget);
        final requester = find.text('A very long wallet requester and automotive business owner name that must wrap safely');
        expect(tester.widget<Text>(requester).textDirection, TextDirection.ltr);
        expect(walletQuery!.queryParameters['select'],
            isNot(contains('profiles')));
        await currentTypographyCheckpoint(tester, 'WALLET_ADMIN');
        if (const bool.fromEnvironment('UI_WALLET_REVIEW_HOLD') &&
            locale == AppLocale.en &&
            dark) {
          debugPrint('UI_WALLET_ADMIN_REVIEW_READY');
          await Future<void>.delayed(const Duration(seconds: 45));
        }
        await openDecision(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        final amount = tester.widget<Text>(find.byKey(const ValueKey('wallet_decision_amount')));
        final owner = tester.widget<Text>(find.byKey(const ValueKey('wallet_decision_requester')));
        expect(amount.data, formatIqd(100000));
        expect(amount.textDirection, TextDirection.ltr);
        expect(owner.textDirection, TextDirection.ltr);
        expect(owner.data, contains('A very long wallet requester'));
        expect(find.text(t('ui_wallet_decision_prompt')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'WALLET_ADMIN_CONFIRM');
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(decisions, 0);
        await finish(tester);
      });
    }
  }
  testWidgets('permission denial differs from a failed access check',
      (tester) async {
    admin = false;
    await mount(tester);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(walletQuery, isNull);
    await finish(tester);
    admin = true;
    accessFails = true;
    await mount(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('admin_only_notice')), findsNothing);
    accessFails = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(formatIqd(100000)), findsOneWidget);
    await finish(tester);
  });
  testWidgets('missing profile names never remove pending requests',
      (tester) async {
    namesFail = true;
    await mount(tester);
    expect(find.text('owner-1'), findsOneWidget);
    expect(find.text('owner-2'), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    await finish(tester);
  });
  for (final failure in ['false', 'wrong_status', 'exception']) {
    testWidgets('$failure response never claims wallet approval success',
        (tester) async {
      mode = failure;
      await mount(tester);
      await openDecision(tester);
      await confirm(tester);
      expect(rows, hasLength(2));
      expect(find.text(t('payment_update_failed')), findsOneWidget);
      expect(find.text(t('wallet_admin_approve_success')), findsNothing);
      expect(find.textContaining('Private'), findsNothing);
      await finish(tester);
    });
  }
  testWidgets(
      'confirmed decision disables duplicates and reloads after success',
      (tester) async {
    decisionGate = Completer<void>();
    await mount(tester);
    await openDecision(tester);
    await confirm(tester);
    expect(decisions, 1);
    expect(
        tester
            .widgetList<FilledButton>(find.byType(FilledButton))
            .every((button) => button.onPressed == null),
        isTrue);
    decisionGate!.complete();
    await frames(tester);
    expect(rows, hasLength(1));
    expect(find.text(t('wallet_admin_approve_success')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('already-decided request refreshes without claiming new success',
      (tester) async {
    mode = 'already_decided';
    await mount(tester);
    await openDecision(tester);
    await confirm(tester);
    expect(find.text(t('ui_wallet_already_decided')), findsOneWidget);
    expect(find.text(t('wallet_admin_approve_success')), findsNothing);
    expect(rows, hasLength(1));
    await finish(tester);
  });
  testWidgets('rejection confirmation calls the rejected decision',
      (tester) async {
    await mount(tester);
    await openDecision(tester, approve: false);
    await confirm(tester, approve: false);
    expect(decisions, 1);
    expect(find.text(t('wallet_admin_reject_success')), findsOneWidget);
    await finish(tester);
  });
  testWidgets('refresh waits for failed read and retries safely',
      (tester) async {
    await mount(tester);
    readGate = Completer<void>();
    var completed = false;
    final pending = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh()
        .then((_) {
      completed = true;
    });
    await frames(tester);
    expect(completed, isFalse);
    listFails = true;
    readGate!.complete();
    await frames(tester);
    await pending;
    expect(completed, isTrue);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    listFails = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(formatIqd(100000)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('receipt failure is localized and restores controls',
      (tester) async {
    await mount(tester);
    final receipt =
        find.widgetWithText(OutlinedButton, t('wallet_receipt')).first;
    await reveal(tester, receipt);
    await tester.tap(receipt);
    await frames(tester);
    expect(receiptRequests, 1);
    expect(find.text(t('wallet_receipt_open_failed')), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    expect(tester.widget<OutlinedButton>(receipt).onPressed, isNotNull);
    await finish(tester);
  });
  testWidgets('closing during decision safely ignores completion',
      (tester) async {
    decisionGate = Completer<void>();
    await mount(tester);
    await openDecision(tester);
    await confirm(tester);
    await finish(tester);
    decisionGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  for (final stage in ['access', 'rows']) {
    testWidgets('wallet admin late $stage cannot restore private requests',
        (tester) async {
      final gate = Completer<void>();
      if (stage == 'access') {
        accessGate = gate;
      } else {
        readGate = gate;
      }
      await mount(tester);
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      expect(find.text(t('admin_only_notice')), findsOneWidget);
      gate.complete();
      await frames(tester);
      expect(find.text(formatIqd(100000)), findsNothing);
      expect(profileReads, 0);
      if (stage == 'access') expect(walletReads, 0);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('wallet admin confirmation rejects a replaced session',
      (tester) async {
    await mount(tester);
    await openDecision(tester);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
    await tester.runAsync(() => supabase.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'fixture-only'));
    await frames(tester);
    await confirm(tester);
    expect(decisions, 0);
    expect(find.text(t('wallet_admin_approve_success')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('wallet admin late decision cannot refresh or announce success',
      (tester) async {
    decisionGate = Completer<void>();
    await mount(tester);
    await openDecision(tester);
    await confirm(tester);
    expect(decisions, 1);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
    final reads = walletReads;
    decisionGate!.complete();
    await frames(tester);
    expect(walletReads, reads);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(find.text(t('wallet_admin_approve_success')), findsNothing);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('wallet admin late receipt failure cannot affect guest state',
      (tester) async {
    receiptGate = Completer<void>();
    await mount(tester);
    final receipt =
        find.widgetWithText(OutlinedButton, t('wallet_receipt')).first;
    await reveal(tester, receipt);
    await tester.tap(receipt);
    await frames(tester);
    expect(receiptRequests, 1);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
    receiptGate!.complete();
    await frames(tester);
    expect(find.text(t('wallet_receipt_open_failed')), findsNothing);
    expect(find.text(t('admin_only_notice')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
}
