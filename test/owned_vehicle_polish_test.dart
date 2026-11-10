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
import 'package:motri_iq/ui/owned_vehicle_dialog.dart';
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

const car = <String, dynamic>{
  'id': 'car-1',
  'user_id': uid,
  'brand': 'Toyota',
  'model': 'Land Cruiser Platinum extended model',
  'year': 2023,
  'price': 34500,
  'city': 'Mansour',
  'province': 'Legacy province',
  'body_type': 'Legacy body',
  'seller_phone': '+9647715339922',
  'description': 'Original vehicle description'
};
void main() {
  final writes = <http.Request>[];
  Completer<void>? gate;
  late Future<List<Map<String, dynamic>>> Function() readCars;
  var reads = 0;
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
          } else if (req.method == 'PATCH' || req.method == 'DELETE') {
            writes.add(req);
            if (gate != null) await gate!.future;
            if (fail) {
              status = 500;
              body = {'message': 'private database detail', 'code': '42501'};
            } else {
              body = noAck
                  ? []
                  : [
                      {'id': wrongAck ? 'other-car' : 'car-1'}
                    ];
            }
          }
          if (req.method == 'GET' && req.url.path.endsWith('/cars')) {
            reads++;
            body = await readCars();
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
    reads = 0;
    readCars = () async => [car];
    gate = null;
    noAck = fail = wrongAck = false;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  Future<void> mount(WidgetTester tester,
      {bool delete = false,
      bool page = false,
      double scale = 1.6,
      double width = 360,
      double keyboard = 0,
      Map<String, dynamic>? data}) async {
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
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(scale),
                    viewInsets:
                        keyboard == 0 || const bool.fromEnvironment('NATIVE_VIEWPORT')
                            ? MediaQuery.of(context).viewInsets
                            : EdgeInsets.only(bottom: keyboard)),
                child: child!),
            home: page
                ? const MyAdsPage()
                : Scaffold(
                    body: Builder(
                        builder: (context) => TextButton(
                            onPressed: () => showDialog<bool>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => OwnedVehicleDialog(
                                    car: Map.of(data ?? car), delete: delete)),
                            child: const Text('Open')))))));
    await frames(tester);
    if (!page) {
      await tester.tap(find.text('Open'));
      await frames(tester);
    }
  }

  Finder field(String name) => find.byKey(ValueKey('owned_$name'));
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> hold(WidgetTester tester, String marker) async {
    if (!const bool.fromEnvironment('UI_OWNED_REVIEW_HOLD')) return;
    debugPrint(marker);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'owned vehicles ${locale.code} dark=$dark enlarged populated and editor',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester, page: true);
        expect(find.textContaining('Land Cruiser'), findsOneWidget);
        expect(find.textContaining('دولار'), findsNothing);
        expect(tester.takeException(), isNull);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'OWNED_LIST_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'MY_ADS');
        }
        await tester.tap(find.text(t('account_edit_ads')));
        await frames(tester);
        expect(field('brand'), findsOneWidget);
        expect(tester.widget<TextField>(field('year')).textDirection,
            TextDirection.ltr);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'OWNED_EDITOR_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'MY_ADS_EDITOR');
        }
        final scroll = find.byType(Scrollable).last;
        await tester.scrollUntilVisible(field('description'), 150,
            scrollable: scroll);
        await frames(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(find.byType(OwnedVehicleDialog), findsNothing);
        await finish(tester);
      });
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('owned editor direction ${locale.code} dark=$dark narrow',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester, width: 320);
        expect(tester.widget<TextField>(field('brand')).textDirection,
            TextDirection.ltr);
        await currentTypographyCheckpoint(tester, 'OWNED_EDITOR_TOP');
        for (final key in ['brand', 'model', 'city', 'description']) {
          await tester.scrollUntilVisible(field(key), 150,
              scrollable: find.byType(Scrollable).last);
          final controller = tester.widget<TextField>(field(key)).controller!;
          const value = TextEditingValue(
              text: 'سيارة Toyota',
              selection: TextSelection.collapsed(offset: 3),
              composing: TextRange(start: 0, end: 5));
          controller.value = value;
          await tester.pump();
          expect(tester.widget<TextField>(field(key)).textDirection,
              TextDirection.rtl);
          expect(controller.value, value);
          controller.text = 'Toyota سيارة';
          await tester.pump();
          expect(tester.widget<TextField>(field(key)).textDirection,
              TextDirection.ltr);
        }
        for (final key in ['year', 'price', 'seller_phone']) {
          expect(tester.widget<TextField>(field(key)).textDirection,
              TextDirection.ltr);
        }
        await currentTypographyCheckpoint(tester, 'OWNED_EDITOR_BOTTOM');
        await tester.tap(find.text(t('common_cancel')));
        await finish(tester);
      });
    }
    testWidgets('owned editor keyboard ${locale.code} enlarged',
        (tester) async {
      appLocaleNotifier.value = locale;
      AppColors.isDark = locale == AppLocale.ku;
      await mount(tester, width: 320, keyboard: 220);
      await tester.scrollUntilVisible(field('description'), 150,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(field('description'));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await frames(tester);
      await tester.enterText(
          field('description'), 'A draft vehicle description');
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)));
      await frames(tester);
      final keyboard = const bool.fromEnvironment('NATIVE_VIEWPORT')
          ? tester.view.viewInsets.bottom / tester.view.devicePixelRatio
          : 220.0;
      expect(tester.widget<TextField>(field('description')).controller!.text,
          'A draft vehicle description');
      expect(keyboard, greaterThan(0));
      await Scrollable.ensureVisible(tester.element(field('description')),
          alignment: .9);
      await frames(tester);
      expect(
          tester.getBottomRight(field('description')).dy,
          lessThanOrEqualTo(
              tester.getTopLeft(find.text(t('common_cancel'))).dy + 1));
      expect(
          tester.getBottomRight(find.text(t('common_cancel'))).dy,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
                  keyboard));
      await currentTypographyCheckpoint(tester, 'OWNED_EDITOR_KEYBOARD');
      await tester.tap(find.text(t('common_cancel')));
      expect(writes, isEmpty);
      await finish(tester);
    });
  }
  Future<void> signIn(WidgetTester tester) async {
    await tester.runAsync(() => supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
    await frames(tester);
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final surface in ['loading', 'error', 'empty']) {
        testWidgets('My Ads $surface ${locale.code} dark=$dark enlarged',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          final pending = Completer<List<Map<String, dynamic>>>();
          readCars = () async {
            if (surface == 'loading') return pending.future;
            if (surface == 'error') throw StateError('private diagnostics');
            return [];
          };
          await mount(tester, page: true);
          if (surface == 'loading') {
            expect(find.byType(CircularProgressIndicator), findsOneWidget);
          } else if (surface == 'error') {
            expect(find.text(t('ui_load_error_title')), findsOneWidget);
            expect(find.textContaining('private diagnostics'), findsNothing);
          } else {
            expect(find.text(t('account_no_published_ads')), findsOneWidget);
          }
          await currentTypographyCheckpoint(
              tester, 'MY_ADS_${surface.toUpperCase()}');
          if (surface == 'loading') {
            pending.complete([car]);
            await frames(tester);
            expect(find.textContaining('Land Cruiser'), findsOneWidget);
          } else if (surface == 'error') {
            readCars = () async => [car];
            await tester.tap(find.text(t('ui_retry')));
            await frames(tester);
            expect(find.textContaining('Land Cruiser'), findsOneWidget);
          }
          await finish(tester);
        });
      }
    }
    for (final surface in ['preview', 'edit', 'delete']) {
      testWidgets('My Ads private $surface expires ${locale.code}',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = locale == AppLocale.ku;
        await mount(tester, page: true);
        if (surface == 'preview') {
          await tester.tap(find.textContaining('Land Cruiser'));
        } else {
          await tester.tap(find.text(
              t(surface == 'edit' ? 'account_edit_ads' : 'common_delete')));
        }
        await frames(tester);
        await signOut(tester);
        expect(find.byKey(const ValueKey('account_scoped_view_expired')),
            findsOneWidget);
        expect(find.byType(OwnedVehicleDialog), findsNothing);
        expect(find.byType(CarDetailsPage), findsNothing);
        expect(find.textContaining('Land Cruiser'), findsNothing);
        await currentTypographyCheckpoint(
            tester, 'MY_ADS_EXPIRED_${surface.toUpperCase()}');
        await signIn(tester);
        expect(find.byKey(const ValueKey('account_scoped_view_expired')),
            findsOneWidget);
        final currentReads = reads;
        await tester.tap(find.byType(BackButton));
        await frames(tester);
        expect(find.textContaining('Land Cruiser'), findsOneWidget);
        expect(writes, isEmpty);
        expect(reads, currentReads,
            reason: 'Expired route cannot refresh the replacement session');
        await finish(tester);
      });
    }
  }
  testWidgets('My Ads late prior-session read cannot restore private rows',
      (tester) async {
    final pending = Completer<List<Map<String, dynamic>>>();
    readCars = () => pending.future;
    await mount(tester, page: true);
    await signOut(tester);
    expect(find.text(t('account_no_published_ads')), findsOneWidget);
    readCars = () async => [
          {...car, 'model': 'Fresh session car'}
        ];
    await signIn(tester);
    pending.complete([car]);
    await frames(tester);
    expect(find.textContaining('Fresh session car'), findsOneWidget);
    expect(find.textContaining('Land Cruiser'), findsNothing);
    await finish(tester);
  });
  testWidgets(
      'localized edit numbers are acknowledged and scoped without clearing legacy selections',
      (tester) async {
    await mount(tester);
    await tester.enterText(field('year'), '٢٠٢٤');
    await tester.enterText(field('price'), '٣٤٬٥٠٠٫٥');
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(writes.length, 1);
    final req = writes.single;
    final body = jsonDecode(req.body);
    expect(body['year'], 2024);
    expect(body['price'], 34500.5);
    expect(body['province'], 'Legacy province');
    expect(body['body_type'], 'Legacy body');
    expect(req.url.queryParameters['id'], 'eq.car-1');
    expect(req.url.queryParameters['user_id'], 'eq.$uid');
    expect(find.byType(OwnedVehicleDialog), findsNothing);
    await finish(tester);
  });
  testWidgets('invalid years and nonfinite or negative amounts never write',
      (tester) async {
    await mount(tester);
    await tester.enterText(field('year'), '٢٢٠٠');
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(writes, isEmpty);
    await tester.ensureVisible(field('year'));
    await tester.tap(field('year'));
    await frames(tester);
    await tester.enterText(field('year'), '٢٠٢٤');
    await frames(tester);
    expect(tester.widget<TextField>(field('year')).controller!.text, '٢٠٢٤');
    for (final amount in ['NaN', 'Infinity', '-1']) {
      await tester.ensureVisible(field('price'));
      await tester.tap(field('price'));
      await frames(tester);
      await tester.enterText(field('price'), amount);
      await frames(tester);
      expect(tester.widget<TextField>(field('year')).controller!.text, '٢٠٢٤');
      expect(tester.widget<TextField>(field('price')).controller!.text, amount);
      await tester.tap(find.text(t('common_save')));
      await frames(tester);
      expect(writes, isEmpty);
      expect(find.text(t('ui_invalid_price')), findsOneWidget,
          reason:
              'amount=$amount year=${tester.widget<TextField>(field('year')).controller!.text}; visible=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().join('|')}');
    }
    await finish(tester);
  });
  for (final delete in [false, true]) {
    for (final failure in ['server', 'no_ack', 'wrong_ack']) {
      testWidgets(
          'owned ${delete ? 'delete' : 'edit'} $failure retains dialog and allows retry',
          (tester) async {
        fail = failure == 'server';
        noAck = failure == 'no_ack';
        wrongAck = failure == 'wrong_ack';
        await mount(tester, delete: delete);
        if (!delete) await tester.enterText(field('brand'), 'Retained draft');
        final action = find.text(t(delete ? 'common_delete' : 'common_save'));
        await tester.tap(action);
        await frames(tester);
        expect(find.byType(OwnedVehicleDialog), findsOneWidget);
        expect(
            find.textContaining(t(delete
                ? 'ui_vehicle_delete_failed'
                : 'ui_vehicle_save_failed')),
            findsOneWidget);
        if (failure == 'server') {
          expect(find.textContaining('42501'), findsOneWidget);
        }
        expect(find.textContaining('private database'), findsNothing);
        if (!delete) {
          expect(tester.widget<TextField>(field('brand')).controller!.text,
              'Retained draft');
        }
        if (failure == 'server') {
          await hold(
              tester, delete ? 'OWNED_DELETE_ERROR' : 'OWNED_EDIT_ERROR');
        }
        fail = noAck = wrongAck = false;
        await tester.tap(action);
        await frames(tester);
        expect(writes.length, 2);
        expect(find.byType(OwnedVehicleDialog), findsNothing);
        await finish(tester);
      });
    }
    testWidgets(
        'owned ${delete ? 'delete' : 'edit'} guards pending actions and disposal',
        (tester) async {
      gate = Completer<void>();
      await mount(tester, delete: delete);
      await tester.tap(find.text(t(delete ? 'common_delete' : 'common_save')));
      await frames(tester);
      expect(writes.length, 1);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, t('common_cancel')))
              .onPressed,
          isNull);
      expect(
          tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
      if (!delete) {
        expect(tester.widget<TextField>(field('brand')).enabled, isFalse);
      }
      await tester.pumpWidget(const SizedBox());
      gate!.complete();
      await frames(tester);
      expect(tester.takeException(), isNull);
    });
  }
  for (final delete in [false, true]) {
    testWidgets(
        'owned ${delete ? 'delete' : 'edit'} rejects another owner and expired session',
        (tester) async {
      await mount(tester,
          delete: delete, data: {...car, 'user_id': 'another-owner'});
      await tester.tap(find.text(t(delete ? 'common_delete' : 'common_save')));
      await frames(tester);
      expect(writes, isEmpty);
      expect(find.text(t('misc_login_first_publish')), findsOneWidget);
      await finish(tester);
      await mount(tester, delete: delete);
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      await tester.tap(find.text(t(delete ? 'common_delete' : 'common_save')));
      await frames(tester);
      expect(writes, isEmpty);
      await finish(tester);
      await tester.runAsync(() => supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture'));
    });
  }
  for (final mode in ['preserve', 'clear']) {
    testWidgets('optional vehicle amounts $mode stay nullable during edits',
        (tester) async {
      await mount(tester, data: {
        ...car,
        if (mode == 'preserve') 'year': null,
        if (mode == 'preserve') 'price': null
      });
      if (mode == 'clear') {
        for (final key in ['year', 'price']) {
          await tester.ensureVisible(field(key));
          await tester.tap(field(key));
          await frames(tester);
          await tester.enterText(field(key), '');
          await frames(tester);
        }
      }
      if (mode == 'preserve') await hold(tester, 'OWNED_OPTIONAL');
      await tester.tap(find.text(t('common_save')));
      await frames(tester);
      expect(writes.length, 1);
      final body = jsonDecode(writes.single.body);
      expect(body['year'], isNull);
      expect(body['price'], isNull);
      expect(body['brand'], 'Toyota');
      expect(find.byType(OwnedVehicleDialog), findsNothing);
      await finish(tester);
    });
  }
}
