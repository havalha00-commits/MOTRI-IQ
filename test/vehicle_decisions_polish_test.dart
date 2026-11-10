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
import 'package:motri_iq/ui/vehicle_sale_dialog.dart';
import 'package:motri_iq/ui/vehicle_report_dialog.dart';
import 'support/current_typography_checkpoint.dart';

const account = '00000000-0000-4000-8000-000000000001';
const other = '00000000-0000-4000-8000-000000000002';
const carId = '11111111-1111-4111-8111-111111111111';
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final writes = <http.Request>[];
  Completer<void>? gate;
  var mode = 'success', remoteStatus = 'active';
  var admin = false, reads = 0;
  Object? result;
  late Map<String, dynamic> car;
  Future<void> signIn() => supabase.auth
      .signInWithPassword(email: 'fixture@example.com', password: 'fixture')
      .then((_) {});
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final token = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': account,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        })))
        .replaceAll('=', '');
    final signature = base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        Object? body = [];
        var status = 200;
        final table = request.url.path.split('/').last;
        if (table == 'token') {
          body = {
            'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.$signature',
            'refresh_token': 'fixture',
            'token_type': 'bearer',
            'expires_in': 3600,
            'user': {
              'id': account,
              'aud': 'authenticated',
              'role': 'authenticated',
              'email': 'fixture@example.com',
              'created_at': '2026-01-01T00:00:00Z'
            }
          };
        } else if (table == 'logout') {
          body = {};
        } else if (table == 'app_admins') {
          body = admin ? {'user_id': account} : null;
        } else if (table == 'cars' && request.method == 'GET') {
          reads++;
          body = [
            {...car, 'status': remoteStatus, 'user_id': account}
          ];
        } else if (request.method == 'PATCH' && table == 'cars' ||
            request.method == 'POST' &&
                ['car_reports', 'admin_delete_ad'].contains(table)) {
          writes.add(request);
          await gate?.future;
          if (mode == 'server' || mode == 'duplicate') {
            status = 400;
            body = {
              'code': mode == 'duplicate' ? '23505' : 'XX000',
              'message': 'private vehicle decision diagnostics'
            };
          } else if (table == 'cars') {
            if (mode != 'wrong_status') remoteStatus = 'sold';
            body = mode == 'empty'
                ? []
                : [
                    {
                      'id': mode == 'wrong_id' ? other : carId,
                      'status': mode == 'wrong_status' ? 'active' : 'sold'
                    }
                  ];
          } else if (table == 'admin_delete_ad') {
            body = {'ok': true, 'deleted': mode == 'empty' ? 0 : 1};
          } else {
            // Ordinary reporters have INSERT permission, without SELECT.
            status = 201;
            body = null;
          }
        } else {
          expectSync(request.method, 'GET',
              reason: 'Only isolated decision writes are permitted');
        }
        return http.Response(jsonEncode(body), status,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    await signIn();
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) await signIn();
    writes.clear();
    gate = null;
    mode = 'success';
    remoteStatus = 'active';
    admin = false;
    reads = 0;
    result = null;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
    car = {
      'id': carId,
      'user_id': account,
      'brand': 'MOTRI',
      'model': 'Family utility vehicle with a readable model name',
      'year': 2025,
      'price': 25000,
      'status': 'active',
      'images': <String>[]
    };
    trustCache.reset();
  });
  tearDownAll(() => supabase.auth.signOut(scope: SignOutScope.local));
  Future<void> mount(WidgetTester tester,
      {bool sale = true,
      bool detail = false,
      bool myAds = false,
      String owner = account,
      double scale = 1.6}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        theme: buildAppTheme(
            AppColors.isDark ? Brightness.dark : Brightness.light),
        builder: (context, child) => AppStringsScope(
            locale: locale,
            child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!)),
        home: myAds
            ? const MyAdsPage()
            : Scaffold(
                body: SafeArea(
                    child: Builder(
                        builder: (context) => TextButton(
                            onPressed: () async {
                              if (detail) {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            CarDetailsPage(car: car)));
                              } else {
                                result = await showDialog<Object>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => sale
                                        ? VehicleSaleDialog(
                                            carId: carId, ownerId: owner)
                                        : const VehicleReportDialog(
                                            carId: carId, sellerId: other));
                              }
                            },
                            child: const Text('Open'))))),
      ),
    ));
    await frames(tester);
    if (!myAds) {
      await tester.tap(find.text('Open'));
      await frames(tester);
    }
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    if (find.byType(Scrollable).evaluate().isNotEmpty) {
      await tester.scrollUntilVisible(target, 250,
          scrollable: find.byType(Scrollable).first, maxScrolls: 50);
      await Scrollable.ensureVisible(tester.element(target), alignment: .5);
      await frames(tester);
    }
  }

  Future<void> submit(WidgetTester tester, bool sale) async {
    final button = find.widgetWithText(
        FilledButton, t(sale ? 'ad_status_yes_sold' : 'report_submit'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final sale in [true, false]) {
        testWidgets(
            '${locale.code} vehicle ${sale ? 'sale' : 'report'} failure dark=$dark',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          mode = 'server';
          await mount(tester, sale: sale);
          if (!sale) {
            expect(find.byType(RadioGroup<String>), findsOneWidget);
            final tile = tester.widget<RadioListTile<String>>(
                find.byType(RadioListTile<String>).first);
            final color = tile.fillColor!.resolve({WidgetState.selected})!;
            final surface =
                Theme.of(tester.element(find.byType(VehicleReportDialog)))
                    .colorScheme
                    .surface;
            final a = color.computeLuminance(), b = surface.computeLuminance();
            expect(((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
                greaterThanOrEqualTo(3));
            await tester.tap(find.text(t('report_duplicate')));
            await frames(tester);
          }
          await submit(tester, sale);
          expect(
              find.text(
                  t(sale ? 'ui_vehicle_sale_failed' : 'report_send_failed')),
              findsOneWidget);
          expect(find.textContaining('private'), findsNothing);
          expect(result, isNull);
          expect(writes, hasLength(1));
          await currentTypographyCheckpoint(
              tester, sale ? 'SALE_FAILURE' : 'REPORT_FAILURE');
          mode = 'success';
          await submit(tester, sale);
          expect(result, sale ? true : 'report_received');
          if (sale) {
            expect(writes.last.url.queryParameters['id'], 'eq.$carId');
            expect(writes.last.url.queryParameters['user_id'], 'eq.$account');
            expect(jsonDecode(writes.last.body), {'status': 'sold'});
          } else {
            final first = jsonDecode(writes.first.body),
                last = jsonDecode(writes.last.body);
            expect(last['id'], first['id']);
            expect(last['reason'], t('report_duplicate'));
            expect(
                writes.last.url.queryParameters.containsKey('select'), isFalse);
            expect(writes.last.headers['Prefer'],
                isNot(contains('representation')));
          }
          await finish(tester);
        });
      }
    }
  }
  for (final failure in ['empty', 'wrong_id', 'wrong_status']) {
    testWidgets(
        'sale $failure acknowledgement keeps dialog and supports idempotent retry',
        (tester) async {
      mode = failure;
      await mount(tester);
      await submit(tester, true);
      expect(result, isNull);
      expect(find.byType(VehicleSaleDialog), findsOneWidget);
      mode = 'success';
      await submit(tester, true);
      expect(result, isTrue);
      expect(writes.map((r) => r.url.queryParameters['id']).toSet(),
          {'eq.$carId'});
      await finish(tester);
    });
  }
  for (final sale in [true, false]) {
    testWidgets('${sale ? 'sale' : 'report'} cancel performs no write',
        (tester) async {
      await mount(tester, sale: sale);
      await tester.tap(find.text(t('common_cancel')));
      await frames(tester);
      expect(writes, isEmpty);
      await finish(tester);
    });
    testWidgets(
        '${sale ? 'sale' : 'report'} pending guards duplicates and disposal',
        (tester) async {
      gate = Completer<void>();
      await mount(tester, sale: sale);
      final action = tester
          .widget<FilledButton>(find.widgetWithText(
              FilledButton, t(sale ? 'ad_status_yes_sold' : 'report_submit')))
          .onPressed!;
      action();
      action();
      await frames(tester);
      expect(writes, hasLength(1));
      expect(
          tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
      expect(
          tester
              .widget<TextButton>(
                  find.widgetWithText(TextButton, t('common_cancel')))
              .onPressed,
          isNull);
      await tester.pumpWidget(const SizedBox());
      gate!.complete();
      await frames(tester);
      expect(result, isNull);
      expect(tester.takeException(), isNull);
    });
    testWidgets(
        '${sale ? 'sale' : 'report'} account loss never confirms the old request',
        (tester) async {
      gate = Completer<void>();
      await mount(tester, sale: sale);
      await submit(tester, sale);
      await tester
          .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
      gate!.complete();
      await frames(tester);
      expect(result, isNull);
      expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
      await tester.runAsync(signIn);
      await finish(tester);
    });
  }
  for (final sale in [true, false]) {
    for (final pending in [false, true]) {
      testWidgets(
          '${sale ? 'sale' : 'report'} same-account return pending=$pending expires dialog',
          (tester) async {
        appLocaleNotifier.value = sale ? AppLocale.ar : AppLocale.ku;
        AppColors.isDark = !sale;
        if (pending) {
          gate = Completer<void>();
        }
        await mount(tester, sale: sale);
        if (pending) {
          await submit(tester, sale);
        }
        await tester
            .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
        await frames(tester);
        await tester.runAsync(signIn);
        await frames(tester);
        if (pending) {
          gate!.complete();
          await frames(tester);
        }
        expect(result, isNull);
        expect(find.text(t('ui_vehicle_session_changed')), findsOneWidget);
        final button = tester.widget<FilledButton>(find.byType(FilledButton));
        expect(button.onPressed, isNull);
        expect(writes, hasLength(pending ? 1 : 0));
        if (pending) {
          await currentTypographyCheckpoint(
              tester, sale ? 'SALE_EXPIRED' : 'REPORT_EXPIRED');
        }
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(find.byType(sale ? VehicleSaleDialog : VehicleReportDialog),
            findsNothing);
        await finish(tester);
      });
    }
  }
  testWidgets(
      'report duplicate is accurate feedback without requiring reporter SELECT',
      (tester) async {
    mode = 'duplicate';
    await mount(tester, sale: false);
    await submit(tester, false);
    expect(result, 'report_already');
    expect(writes.single.url.queryParameters.containsKey('select'), isFalse);
    await finish(tester);
  });
  testWidgets(
      'report reason follows a live locale switch without losing its selection',
      (tester) async {
    await mount(tester, sale: false);
    await tester.ensureVisible(find.text(t('support_issue_scam')));
    await frames(tester);
    await tester.tap(find.text(t('support_issue_scam')));
    await frames(tester);
    appLocaleNotifier.value = AppLocale.ku;
    await frames(tester);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'support_issue_scam');
    await submit(tester, false);
    expect(jsonDecode(writes.single.body)['reason'], t('support_issue_scam'));
    await finish(tester);
  });
  testWidgets('foreign owner cannot mark another vehicle sold', (tester) async {
    await mount(tester, owner: other);
    await submit(tester, true);
    expect(writes, isEmpty);
    expect(result, isNull);
    await finish(tester);
  });
  for (final locale in [AppLocale.ar, AppLocale.ku]) {
    testWidgets(
        '${locale.code} owner sale updates detail and refreshes My ads without mutating its input',
        (tester) async {
      appLocaleNotifier.value = locale;
      AppColors.isDark = locale == AppLocale.ku;
      await mount(tester, myAds: true);
      await tester.tap(find.text('${car['brand']} ${car['model']}'));
      await frames(tester);
      final borrowed =
          tester.widget<CarDetailsPage>(find.byType(CarDetailsPage)).car;
      await reveal(tester, find.text(t('ui_mark_vehicle_sold')));
      await tester.tap(find.text(t('ui_mark_vehicle_sold')));
      await frames(tester);
      await submit(tester, true);
      expect(find.text(t('ui_mark_vehicle_sold')), findsNothing);
      expect(find.text(t('ad_status_sold_check')), findsOneWidget);
      expect(borrowed['status'], 'active');
      await tester.tap(find.byType(BackButton));
      await frames(tester);
      expect(reads, greaterThanOrEqualTo(2));
      expect(find.byKey(const ValueKey('owned_vehicle_sold:$carId')),
          findsOneWidget);
      await currentTypographyCheckpoint(tester, 'OWNED_SOLD');
      await finish(tester);
    });
  }
  testWidgets(
      'actual report route prevents duplicate dialogs and shows the confirmed outcome',
      (tester) async {
    car['user_id'] = other;
    await mount(tester, detail: true);
    await reveal(tester, find.text(t('report_ad')));
    await tester.tap(find.text(t('report_ad')));
    await frames(tester);
    expect(find.byType(VehicleReportDialog), findsOneWidget);
    await submit(tester, false);
    expect(find.text(t('report_received')), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'detail admin delete guards confirmation requests and rejects a no-op',
      (tester) async {
    admin = true;
    await mount(tester, detail: true);
    final action = tester
        .widget<IconButton>(find.byWidgetPredicate((widget) =>
            widget is IconButton && widget.tooltip == t('admin_delete_ad')))
        .onPressed!;
    action();
    action();
    await frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(writes, isEmpty);
    gate = Completer<void>();
    mode = 'empty';
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    await tester.tap(find.widgetWithText(FilledButton, t('common_delete')));
    await frames(tester);
    expect(writes, hasLength(1));
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate((widget) =>
                widget is IconButton && widget.tooltip == t('admin_delete_ad')))
            .onPressed,
        isNull);
    gate!.complete();
    await frames(tester);
    expect(find.byType(CarDetailsPage), findsOneWidget);
    expect(find.text(t('admin_delete_ad_failed')), findsOneWidget);
    expect(jsonDecode(writes.single.body), {'p_table': 'cars', 'p_id': carId});
    await finish(tester);
  });
}
