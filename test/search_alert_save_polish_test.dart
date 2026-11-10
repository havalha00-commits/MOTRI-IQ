import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final payloads = <Map<String, dynamic>>[];
  var fail = false, noAck = false;
  Completer<void>? gate;
  late BackendApi previousBackendApi;
  const uid = '00000000-0000-4000-8000-000000000001';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    previousBackendApi = backendApi;
    final jwt = base64Url
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
        httpClient: MockClient((request) async {
          Object body = [];
          var status = 200;
          if (request.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$jwt.$signature',
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
          return http.Response(jsonEncode(body), status,
              request: request, headers: {'content-type': 'application/json'});
        }));
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      client: MockClient((request) async {
        if (request.url.path == '/api/activity/saved-searches') {
          payloads
              .add(Map<String, dynamic>.from(jsonDecode(request.body) as Map));
          if (gate != null) await gate!.future;
          final responseBody = fail
              ? {'error': 'private backend detail'}
              : noAck
                  ? <String, dynamic>{'success': true, 'data': null}
                  : {
                      'success': true,
                      'data': {'id': 'saved-fixture'}
                    };
          return http.Response(
            jsonEncode(responseBody),
            fail ? 500 : 201,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'data': <dynamic>[]}),
          200,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() {
    payloads.clear();
    fail = noAck = false;
    gate = null;
    appLocaleNotifier.value = AppLocale.en;
  });
  tearDownAll(() async {
    backendApi = previousBackendApi;
    await supabase.auth.signOut(scope: SignOutScope.local);
  });
  Future<SearchTabState> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const Scaffold(body: SafeArea(child: SearchTab()))));
    await frames(tester);
    return tester.state<SearchTabState>(find.byType(SearchTab));
  }

  testWidgets(
      'unified supported filters are saved with localized numeric values',
      (tester) async {
    final state = await mount(tester);
    state.advanced
      ..brand = 'Toyota'
      ..city = 'بغداد'
      ..bodyType = 'SUV'
      ..fromYear = '٢٠٢٠'
      ..minPrice = '١٠٬٠٠٠';
    unawaited(state.saveSearchAlert());
    await frames(tester);
    expect(payloads.single, containsPair('user_id', uid));
    expect(payloads.single, containsPair('brand', 'Toyota'));
    expect(payloads.single, containsPair('city', 'بغداد'));
    expect(payloads.single, containsPair('body_type', 'SUV'));
    expect(payloads.single, containsPair('min_year', 2020));
    expect(payloads.single, containsPair('min_price', 10000));
    expect(find.text(t('alerts_saved')), findsOneWidget);
  });
  testWidgets(
      'typed Arabic make and year save canonical criteria, not literal text',
      (tester) async {
    final state = await mount(tester);
    state.controller.text = 'نيسان ٢٠٢٢';
    await state.saveSearchAlert();
    await frames(tester);
    expect(payloads.single['query_text'], isNull);
    expect(payloads.single['brand'], 'Nissan');
    expect(payloads.single['min_year'], 2022);
    expect(payloads.single['max_year'], 2022);
  });
  testWidgets(
      'regional and free-text matching cannot be silently narrowed in an alert',
      (tester) async {
    final state = await mount(tester);
    state.advanced.province = 'Baghdad';
    await state.saveSearchAlert();
    await frames(tester);
    expect(payloads, isEmpty);
    expect(find.text(t('ui_alert_criteria_limit')), findsOneWidget);
  });
  testWidgets('unsupported alert criteria are explained rather than discarded',
      (tester) async {
    final state = await mount(tester);
    state.advanced
      ..brand = 'Toyota'
      ..model = 'Camry';
    unawaited(state.saveSearchAlert());
    await frames(tester);
    expect(payloads, isEmpty);
    expect(find.text(t('ui_alert_criteria_limit')), findsOneWidget);
  });
  testWidgets('save guard, generic failure, no-ack and retry', (tester) async {
    final state = await mount(tester);
    state.controller.text = 'Toyota';
    gate = Completer<void>();
    fail = true;
    unawaited(state.saveSearchAlert());
    await frames(tester);
    unawaited(state.saveSearchAlert());
    await frames(tester);
    expect(payloads.length, 1);
    gate!.complete();
    await frames(tester);
    gate = null;
    expect(find.text(t('ui_alert_save_failed')), findsOneWidget);
    expect(find.textContaining('private backend'), findsNothing);
    fail = false;
    noAck = true;
    unawaited(state.saveSearchAlert());
    await frames(tester);
    expect(find.text(t('alerts_saved')), findsNothing);
    noAck = false;
    unawaited(state.saveSearchAlert());
    await frames(tester);
    expect(find.text(t('alerts_saved')), findsOneWidget);
    expect(state.savingAlert, isFalse);
  });
  testWidgets('pending save can finish after leaving Search', (tester) async {
    final state = await mount(tester);
    state.controller.text = 'Toyota';
    gate = Completer<void>();
    unawaited(state.saveSearchAlert());
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
}
