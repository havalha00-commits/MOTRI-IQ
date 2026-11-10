import 'dart:convert';
import 'dart:async';
import 'support/current_typography_checkpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/wallet/wallet_admin_review_page.dart';
import 'package:motri_iq/ui/app_state_panel.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final failingTables = <String>{};
  final reads = <String, int>{};
  Completer<void>? readGate;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    const userId = '00000000-0000-4000-8000-000000000001';
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': userId,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        })))
        .replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((request) async {
          final path = request.url.path;
          Object body = [];
          var status = 200;
          if (path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
              'refresh_token': 'fixture-refresh-token',
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
          } else if (path == '/auth/v1/logout') {
            body = {};
          } else if (path == '/rest/v1/app_admins') {
            body = {'user_id': userId};
          } else {
            expectSync(request.method, 'GET',
                reason: 'State review must not mutate data');
            final table = path.split('/').last;
            if (readGate != null) await readGate!.future;
            reads.update(table, (n) => n + 1, ifAbsent: () => 1);
            if (failingTables.contains(table)) {
              status = 400;
              body = {
                'message':
                    'Internal fixture error that must not appear in the UI'
              };
            }
          }
          return http.Response(jsonEncode(body), status,
              request: request,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    await Supabase.instance.client.auth.signInWithPassword(
        email: 'fixture@example.com', password: 'local-fixture-only');
  });
  tearDown(() {
    failingTables.clear();
    readGate = null;
    appLocaleNotifier.value = AppLocale.ar;
  });
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));

  for (final locale in AppLocale.values) {
    testWidgets(
        '${locale.code}: short screen large-text state action remains reachable',
        (tester) async {
      tester.view.physicalSize = const Size(320, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      appLocaleNotifier.value = locale;
      var retries = 0;
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.dark),
          home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
              child: Directionality(
                  textDirection: locale.direction,
                  child: Scaffold(
                      body: AppStateView(
                    title: t('ui_load_error_title'),
                    message: t('ui_load_error_body'),
                    icon: Icons.cloud_off_rounded,
                    isError: true,
                    actionLabel: t('ui_retry'),
                    onAction: () => retries++,
                  ))))));
      await frames(tester);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.tap(find.byType(FilledButton));
      expect(retries, 1);
    });
  }

  final listPages = <(String, Widget, String)>[
    ('cars', const MyAdsPage(), 'account_no_published_ads'),
    ('car_offers', const MyMessagesPage(), 'chat_empty'),
    ('car_offers', const MySentOffersPage(), 'account_no_sent_offers'),
    ('seller_reviews', const MyReviewsPage(), 'account_no_reviews'),
    ('car_reports', const AdminDashboardPage(), 'report_no_reports'),
    ('business_ads', const AdminBusinessAdsPage(), 'misc_no_ads_status'),
    (
      'activity_notifications',
      const ActivityNotificationsPage(),
      'alerts_empty_now'
    ),
    ('car_alerts', const AlertsPage(), 'alerts_empty'),
    ('user_follows', const MyFollowsPage(), 'account_not_following'),
    ('wallet_transactions', const WalletAdminReviewPage(), 'wallet_no_pending'),
  ];
  for (final entry in listPages) {
    testWidgets('${entry.$2.runtimeType}: delayed read shows loading before empty',
        (tester) async {
      appLocaleNotifier.value = entry.$2 is MyAdsPage ? AppLocale.ku : AppLocale.ar;
      AppColors.isDark = true;
      readGate = Completer<void>();
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: entry.$2));
      await frames(tester);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text(t(entry.$3)), findsNothing,
          reason: 'A pending read is not an empty response');
      expect(find.text(t('ui_load_error_title')), findsNothing);
      expect(tester.takeException(), isNull);
      // Capture only one representative of the shared loading component;
      // every list retains its own route-level assertions.
      if (entry.$2 is MyAdsPage) {
        await currentTypographyCheckpoint(tester, 'ACCOUNT_LIST_LOADING');
      }
      readGate!.complete();
      await frames(tester);
      expect(find.text(t(entry.$3)), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final entry in listPages) {
    testWidgets(
        '${entry.$2.runtimeType}: failure retry becomes successful empty state',
        (tester) async {
      failingTables.add(entry.$1);
      await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(Brightness.light),
          home: entry.$2));
      await frames(tester);
      if (entry.$2 is AlertsPage) {
        expect(find.text(t('account_car_alerts')), findsOneWidget);
      }
      expect(find.text(t('ui_load_error_title')), findsOneWidget);
      expect(find.textContaining('Internal fixture'), findsNothing);
      if (const bool.fromEnvironment('UI_REVIEW_HOLD') &&
          entry.$1 == 'car_reports') {
        debugPrint('UI_REVIEW_READY: admin report error state');
        await Future<void>.delayed(const Duration(seconds: 15));
      }
      final before = reads[entry.$1] ?? 0;
      failingTables.remove(entry.$1);
      await tester.tap(find.text(t('ui_retry')));
      await frames(tester);
      expect(reads[entry.$1], greaterThan(before));
      expect(find.text(t(entry.$3)), findsOneWidget);
      if (entry.$2 is AdminDashboardPage) {
        expect(find.text(t('ui_reports_title')), findsOneWidget);
        await tester.tap(find.byType(PopupMenuButton<String>));
        await frames(tester);
        await tester.tap(find.text(t('account_business_ads_all')));
        await frames(tester);
        expect(find.byType(AdminBusinessAdsPage), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await frames(tester);
      }
      expect(find.text(t('ui_load_error_title')), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
