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
import 'package:motri_iq/ui/vehicle_offer_dialog.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

const uid = '00000000-0000-4000-8000-000000000001';
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  final writes = <http.Request>[];
  Completer<void>? gate;
  var noAck = false, fail = false, wrongAck = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token = base64Url
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
        httpClient: MockClient((req) async {
          Object? body = [];
          var status = 200;
          if (req.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.$signature',
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
          } else if (req.url.path == '/auth/v1/logout') {
            body = {};
          } else if (req.method == 'POST') {
            writes.add(req);
            if (gate != null) await gate!.future;
            if (fail) {
              status = 500;
              body = {'message': 'private database detail', 'code': 'XX000'};
            } else {
              body = noAck
                  ? []
                  : [
                      {
                        'id': wrongAck
                            ? 'other-offer'
                            : jsonDecode(req.body)['id']
                      }
                    ];
            }
          }
          return http.Response(jsonEncode(body), status,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() {
    writes.clear();
    gate = null;
    noAck = fail = wrongAck = false;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  Future<void> mount(WidgetTester tester,
      {String seller = 'seller-2',
      double scale = 1.6,
      double width = 360}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(AppStringsScope(
        locale: appLocale,
        child: MaterialApp(
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
            home: Scaffold(
                body: SafeArea(
                    child: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => VehicleOfferDialog(
                                    carId: 'car-1',
                                    sellerId: seller,
                                    carTitle: 'Toyota Land Cruiser',
                                    originalPrice: '٣٤٬٥٠٠')),
                            child: const Text('Open'))))))));
    await frames(tester);
    await tester.tap(find.text('Open'));
    await frames(tester);
  }

  final amount = find.byKey(const ValueKey('offer_amount')),
      message = find.byKey(const ValueKey('offer_message'));
  Future<void> input(WidgetTester tester, Finder field, String value) async {
    await tester.ensureVisible(field);
    await tester.tap(field);
    await frames(tester);
    await tester.enterText(field, value);
    await frames(tester);
    expect(tester.widget<TextField>(field).controller!.text, value);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> hold(WidgetTester tester, String marker) async {
    if (!const bool.fromEnvironment('UI_OFFER_REVIEW_HOLD')) return;
    debugPrint(marker);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'offer draft ${locale.code} dark=$dark direction and recovery',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester);
        await input(tester, amount, '٣٣٠٠٠');
        await tester.ensureVisible(message);
        final controller = tester.widget<TextField>(message).controller!;
        const draft = TextEditingValue(
            text: 'English offer message',
            selection: TextSelection(baseOffset: 1, extentOffset: 7),
            composing: TextRange(start: 0, end: 7));
        controller.value = draft;
        await frames(tester);
        expect(
            tester.widget<TextField>(message).textDirection, TextDirection.ltr);
        expect(controller.value, draft);
        await tester.enterText(message, 'رسالة العرض');
        await frames(tester);
        expect(
            tester.widget<TextField>(message).textDirection, TextDirection.rtl);
        expect(
            tester.widget<TextField>(amount).textDirection, TextDirection.ltr);
        await currentTypographyCheckpoint(tester, 'OFFER_DRAFT');
        fail = true;
        await tester.tap(find.text(t('req_send_offer')));
        await frames(tester);
        expect(find.text(t('ui_vehicle_offer_unconfirmed')), findsOneWidget);
        expect(controller.text, 'رسالة العرض');
        await currentTypographyCheckpoint(tester, 'OFFER_DRAFT_RECOVERY');
        fail = false;
        await tester.tap(find.text(t('req_send_offer')));
        await frames(tester);
        expect(writes, hasLength(2));
        expect(jsonDecode(writes.first.body)['id'],
            jsonDecode(writes.last.body)['id']);
        expect(jsonDecode(writes.last.body)['message'], 'رسالة العرض');
        expect(find.byType(VehicleOfferDialog), findsNothing);
        await finish(tester);
      });
      testWidgets(
          'offer ${locale.code} dark=$dark enlarged keyboard and validation',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester);
        await input(tester, amount, '-١');
        await tester.tap(find.text(t('req_send_offer')));
        await frames(tester);
        expect(find.text(t('req_price_positive')), findsOneWidget);
        expect(writes, isEmpty);
        expect(
            tester.widget<TextField>(amount).textDirection, TextDirection.ltr);
        expect(
            tester.widget<TextField>(message).textDirection, locale.direction);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'OFFER_${locale.code.toUpperCase()}');
        }
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          await frames(tester);
          expect(tester.takeException(), isNull);
          tester.view.resetViewInsets();
        }
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(find.byType(VehicleOfferDialog), findsNothing);
        await finish(tester);
      });
    }
  }
  testWidgets(
      'offer localized amount and asking price persist with matching acknowledgement',
      (tester) async {
    await mount(tester);
    await input(tester, amount, '٣٣٬٠٠٠٫٥');
    await input(tester, message, 'Interested in this car');
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(writes.length, 1);
    final body = jsonDecode(writes.single.body);
    expect(body['offer_price'], 33000.5);
    expect(body['original_price'], 34500);
    expect(body['car_id'], 'car-1');
    expect(body['buyer_id'], uid);
    expect(body['seller_id'], 'seller-2');
    expect(body['message'], 'Interested in this car');
    expect(
        body['id'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(find.byType(VehicleOfferDialog), findsNothing);
    await finish(tester);
  });
  for (final failure in ['server', 'no_ack', 'wrong_ack']) {
    testWidgets('offer $failure retains draft and stable retry id',
        (tester) async {
      fail = failure == 'server';
      noAck = failure == 'no_ack';
      wrongAck = failure == 'wrong_ack';
      await mount(tester);
      await input(tester, amount, '٣٣٠٠٠');
      await input(tester, message, 'Retain this message');
      await tester.tap(find.text(t('req_send_offer')));
      await frames(tester);
      expect(find.text(t('ui_vehicle_offer_unconfirmed')), findsOneWidget);
      expect(find.textContaining('private database'), findsNothing);
      expect(tester.widget<TextField>(message).controller!.text,
          'Retain this message');
      expect(tester.widget<TextField>(amount).controller!.text, '٣٣٠٠٠');
      if (failure == 'server') await hold(tester, 'OFFER_RECOVERY');
      fail = noAck = wrongAck = false;
      await tester.tap(find.text(t('req_send_offer')));
      await frames(tester);
      expect(writes.length, 2);
      expect(
          jsonDecode(writes[0].body)['id'], jsonDecode(writes[1].body)['id']);
      expect(find.byType(VehicleOfferDialog), findsNothing);
      await finish(tester);
    });
  }
  testWidgets('offer pending actions and disposal stay safe', (tester) async {
    gate = Completer<void>();
    await mount(tester);
    await input(tester, amount, '٣٣٠٠٠');
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(writes.length, 1);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<TextField>(amount).enabled, isFalse);
    expect(tester.widget<TextField>(message).enabled, isFalse);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('offer rejects nonfinite and zero values', (tester) async {
    await mount(tester);
    for (final value in ['0', 'NaN', 'Infinity']) {
      await input(tester, amount, value);
      await tester.tap(find.text(t('req_send_offer')));
      await frames(tester);
      expect(writes, isEmpty);
      expect(find.text(t('req_price_positive')), findsOneWidget);
    }
    await finish(tester);
  });
  testWidgets('offer prevents self offers and expired sessions',
      (tester) async {
    await mount(tester, seller: uid);
    await input(tester, amount, '33000');
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(writes, isEmpty);
    expect(find.text(t('req_cannot_price')), findsOneWidget);
    await finish(tester);
    await mount(tester);
    await input(tester, amount, '33000');
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(writes, isEmpty);
    expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
    await finish(tester);
    await tester.runAsync(() => supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
  });
  for (final pending in [false, true]) {
    testWidgets('offer same-account return pending=$pending expires action',
        (tester) async {
      await mount(tester);
      await input(tester, amount, '33000');
      if (pending) {
        gate = Completer<void>();
        await tester.tap(find.text(t('req_send_offer')));
        await frames(tester);
      }
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await frames(tester);
      await tester.runAsync(() => supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture'));
      await frames(tester);
      if (pending) {
        gate!.complete();
        await frames(tester);
      }
      expect(find.byType(VehicleOfferDialog), findsOneWidget);
      expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(writes, hasLength(pending ? 1 : 0));
      await tester.tap(find.text(t('common_cancel')));
      await frames(tester);
      await finish(tester);
    });
  }
  testWidgets(
      'offer regular text keeps error feedback separate from the button row',
      (tester) async {
    await mount(tester, scale: 1, width: 420);
    await input(tester, amount, '0');
    await tester.tap(find.text(t('req_send_offer')));
    await frames(tester);
    expect(find.text(t('req_price_positive')), findsOneWidget);
    final cancel =
        tester.getRect(find.widgetWithText(TextButton, t('common_cancel')));
    final send = tester.getRect(find.byType(FilledButton));
    expect((cancel.center.dy - send.center.dy).abs(), lessThan(2),
        reason: 'Short actions should share a row when space is available');
    await hold(tester, 'OFFER_REGULAR');
    await finish(tester);
  });
}
