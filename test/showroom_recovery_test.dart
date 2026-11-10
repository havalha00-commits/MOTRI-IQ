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
import 'support/current_typography_checkpoint.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final payloads = <Map<String, dynamic>>[];
  var fail = false, noAck = false, failLoad = false;
  Completer<void>? loadGate;
  Completer<void>? gate;
  const uid = '00000000-0000-4000-8000-000000000001';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
          } else if (request.url.path.endsWith('/seller_showrooms')) {
            if (request.method == 'GET') {
              if (loadGate != null) await loadGate!.future;
              body = failLoad
                  ? {'message': 'private backend detail'}
                  : [
                      {
                        'seller_id': uid,
                        'showroom_name': 'Existing showroom',
                        'city': 'Baghdad'
                      }
                    ];
              status = failLoad ? 500 : 200;
            } else {
              payloads.add(
                  Map<String, dynamic>.from(jsonDecode(request.body) as Map));
              if (gate != null) await gate!.future;
              body = fail
                  ? {'message': 'private backend detail'}
                  : noAck
                      ? []
                      : {'seller_id': uid};
              status = fail ? 500 : 200;
            }
          }
          return http.Response(jsonEncode(body), status,
              request: request, headers: {'content-type': 'application/json'});
        }));
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture');
    }
    payloads.clear();
    fail = noAck = failLoad = false;
    gate = loadGate = null;
    appLocaleNotifier.value = AppLocale.en;
  });
  Future<dynamic> mount(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: const ManageShowroomPage()));
    await frames(tester);
    return tester.state(find.byType(ManageShowroomPage));
  }

  testWidgets('state gap showroom delayed loading', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    loadGate = Completer<void>();
    await mount(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await currentTypographyCheckpoint(tester, 'GAP_SHOWROOM_LOADING');
    loadGate!.complete();
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(TextField), findsNWidgets(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in AppLocale.values) {
    testWidgets('showroom typed direction and compact fields ${locale.code}',
        (tester) async {
      appLocaleNotifier.value = locale;
      final dynamic state = await mount(tester);
      final nameField = find.byWidgetPredicate((w) =>
          w is TextField && w.controller == state.name);
      final phoneField = find.byWidgetPredicate((w) =>
          w is TextField && w.controller == state.phone);
      for (final sample in ['Erbil showroom', 'معرض أربيل']) {
        state.name.text = sample;
        await tester.pump();
        final field = tester.widget<TextField>(nameField);
        expect(field.textDirection,
            sample.startsWith('Erbil') ? TextDirection.ltr : TextDirection.rtl);
        expect(field.controller, same(state.name));
        expect(field.style?.fontSize, 14);
        expect(field.decoration?.labelText, isNull);
        expect(find.text(t('field_showroom_name')), findsOneWidget);
      }
      await tester.scrollUntilVisible(phoneField, 200,
          scrollable: find.byType(Scrollable).first);
      expect(tester.widget<TextField>(phoneField).textDirection, TextDirection.ltr);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
      'failed load blocks editing and retries without exposing backend details',
      (tester) async {
    failLoad = true;
    final dynamic state = await mount(tester);
    expect(find.text(t('ui_showroom_load_failed')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('private backend'), findsNothing);
    failLoad = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.byType(TextField), findsNWidgets(5));
    expect(state.loadError, isNull);
  });
  testWidgets(
      'name bounds prevent writes and failed save retains draft for retry',
      (tester) async {
    final dynamic state = await mount(tester);
    state.name.text = 'A' * 81;
    await state.saveShowroom();
    await tester.pump();
    expect(payloads, isEmpty);
    expect(state.saveError, 'ui_showroom_name_length');
    state.name.text = 'My showroom';
    state.city.text = 'Erbil';
    fail = true;
    unawaited(state.saveShowroom());
    await frames(tester);
    expect(state.saveError, 'ui_showroom_save_failed');
    expect(state.name.text, 'My showroom');
    expect(state.city.text, 'Erbil');
    noAck = true;
    fail = false;
    unawaited(state.saveShowroom());
    await frames(tester);
    expect(state.saveError, 'ui_showroom_save_failed');
    expect(payloads.length, 2);
    expect(payloads.last['seller_id'], uid);
  });
  testWidgets('pending save ignores duplicate calls and disposal is safe',
      (tester) async {
    final dynamic state = await mount(tester);
    state.name.text = 'My showroom';
    gate = Completer<void>();
    unawaited(state.saveShowroom());
    await frames(tester);
    unawaited(state.saveShowroom());
    await frames(tester);
    expect(payloads.length, 1);
    expect(state.saving, isTrue);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('late load never writes disposed controllers', (tester) async {
    loadGate = Completer<void>();
    await mount(tester);
    await tester.pumpWidget(const SizedBox());
    loadGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending save cannot confirm success after account loss',
      (tester) async {
    final dynamic state = await mount(tester);
    gate = Completer<void>();
    unawaited(state.saveShowroom());
    await frames(tester);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    gate!.complete();
    await frames(tester);
    expect(state.saveError, 'ui_business_session_changed');
    expect(find.text(t('misc_showroom_saved')), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await state.saveShowroom();
    expect(payloads.length, 1);
  });
  testWidgets('acknowledged save returns success to caller', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                              builder: (_) => const ManageShowroomPage()));
                    },
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await frames(tester);
    final dynamic state = tester.state(find.byType(ManageShowroomPage));
    expect(state.name.text, 'Existing showroom');
    unawaited(state.saveShowroom());
    await frames(tester);
    expect(state.saveError, isNull);
    expect(state.saving, isFalse);
    expect(payloads.length, 1);
    expect(result, isTrue);
    expect(find.byType(ManageShowroomPage), findsNothing);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('showroom recovery layout ${locale.code} dark=$dark',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        fail = true;
        await tester.pumpWidget(MaterialApp(
            locale: locale.locale,
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(1.4)),
                child: child!),
            home: const Scaffold(),
          initialRoute: '/showroom',
          routes: {'/showroom': (_) => const ManageShowroomPage()}));
        await frames(tester);
        await currentTypographyCheckpoint(tester, 'SHOWROOM_FORM');
        final dynamic state = tester.state(find.byType(ManageShowroomPage));
        unawaited(state.saveShowroom());
        await frames(tester);
        await tester.scrollUntilVisible(find.text(t('ui_showroom_save_failed')), 250, scrollable: find.byType(Scrollable).first);
        await tester.pump();
        expect(find.text(t('ui_showroom_save_failed')), findsOneWidget);
        expect(state.city.text, 'Baghdad');
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'SHOWROOM_RECOVERY');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
