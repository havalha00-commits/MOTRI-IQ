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
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/auth/auth_capabilities.dart';
import 'package:motri_iq/ui/account_navigation_tile.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 25; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  final requests = <Uri>[];
  const newest =
      'Toyota Land Cruiser Platinum with a long saved search description';
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
          requests.add(request.url);
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
  });
  setUp(() {
    requests.clear();
    SharedPreferences.setMockInitialValues({
      'search_history': [newest, 'Older query', 'Older query', '']
    });
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
    darkModeNotifier.value = ThemeMode.light;
  });
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
  Future<void> mount(WidgetTester tester, Widget page,
      {bool dark = false}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = dark;
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

  final pages = <String, Widget Function()>{
    'settings': () => const SettingsPage(),
    'history': () => const SearchHistoryPage(),
    'fines': () => FinesPage(linkLauncher: (_) async => false)
  };
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final entry in pages.entries) {
        testWidgets('${locale.code} ${entry.key} dark=$dark large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          await mount(tester, entry.value(), dark: dark);
          expect(tester.takeException(), isNull);
          if (entry.key == 'history') {
            expect(
                tester
                    .widget<AccountNavigationTile>(
                        find.byType(AccountNavigationTile).first)
                    .title,
                newest);
            expect(find.byType(AccountNavigationTile), findsNWidgets(2));
          }
          await currentTypographyCheckpoint(tester, entry.key.toUpperCase());
          if (const bool.fromEnvironment('UI_SETTINGS_HISTORY_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark) {
            debugPrint('UI_${entry.key.toUpperCase()}_POLISH_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          if (entry.key == 'settings') {
            expect(find.text(t('account_delete_title')), findsNothing);
            final about = find.text(t('settings_about'));
            await tester.scrollUntilVisible(about, 250,
                scrollable: find.byType(Scrollable).first);
            await frames(tester);
            expect(find.byIcon(Icons.chevron_right_rounded), findsWidgets);
          }
          expect(tester.takeException(), isNull);
          await finish(tester);
        });
      }
    }
  }
  testWidgets('settings persistence and storage failures have feedback',
      (tester) async {
    var fail = true;
    Future<SharedPreferences> loader() async {
      if (fail) throw StateError('Private storage error');
      return SharedPreferences.getInstance();
    }

    await mount(tester, SettingsPage(preferencesLoader: loader));
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    fail = false;
    await tester.ensureVisible(find.text(t('ui_retry')));
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(t('ui_load_error_title')), findsNothing);
    final push = find.byType(Switch).first;
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await frames(tester);
    await tester.tap(push);
    await frames(tester);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('motri.notifications.push'),
        isFalse);
    fail = true;
    await tester.tap(push);
    await frames(tester);
    expect(find.text(t('ui_settings_save_failed')), findsOneWidget);
    expect(tester.widget<Switch>(push).value, isFalse,
        reason: 'Failed writes restore the saved value');
    expect(tester.widget<Switch>(push).onChanged, isNotNull);
    expect(find.textContaining('Private'), findsNothing);
    await finish(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('History delayed read ${locale.code} dark=$dark', (tester) async {
        appLocaleNotifier.value = locale;
        final gate = Completer<void>();
        var pending = true, failRead = dark;
        await mount(tester, SearchHistoryPage(preferencesLoader: () async {
          if (pending) await gate.future;
          if (failRead) throw StateError('private fixture storage failure');
          return SharedPreferences.getInstance();
        }), dark: dark);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.text(t('history_empty')), findsNothing);
        expect(find.text(newest), findsNothing);
        await currentTypographyCheckpoint(tester, 'HISTORY_LOADING');
        pending = false;
        gate.complete();
        if (dark) {
          await frames(tester);
          expect(find.text(t('ui_load_error_title')), findsOneWidget);
          expect(find.text(t('history_empty')), findsNothing);
          failRead = false;
          await tester.tap(find.text(t('ui_retry')));
        }
        await frames(tester);
        expect(find.text(newest), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await finish(tester);
      });
    }
  }

  testWidgets('history load failure retries without becoming empty',
      (tester) async {
    var fail = true;
    Future<SharedPreferences> loader() async {
      if (fail) throw StateError('Private storage error');
      return SharedPreferences.getInstance();
    }

    await mount(tester, SearchHistoryPage(preferencesLoader: loader));
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('history_empty')), findsNothing);
    fail = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text(newest), findsOneWidget);
    await finish(tester);
  });
  for (final locale in [AppLocale.ar, AppLocale.ku]) {
    testWidgets(
        '${locale.code} history clear cancels, then confirms with persistent removal',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester, const SearchHistoryPage(),
          dark: locale == AppLocale.ku);
      await tester.tap(find.byTooltip(t('history_clear')));
      await frames(tester);
      expect(tester.takeException(), isNull);
      await currentTypographyCheckpoint(tester, 'HISTORY_CONFIRM');
      await tester.tap(find.text(t('common_cancel')));
      await frames(tester);
      expect(find.text(newest), findsOneWidget);
      await tester.tap(find.byTooltip(t('history_clear')));
      await frames(tester);
      final confirm = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, t('history_clear')));
      await tester.tap(confirm);
      await frames(tester);
      expect(find.text(t('history_empty')), findsOneWidget);
      expect(
          (await SharedPreferences.getInstance())
              .getStringList('search_history'),
          isNull);
      await finish(tester);
    });
  }
  testWidgets('failed clear keeps history and restores action', (tester) async {
    var calls = 0;
    Future<SharedPreferences> loader() async {
      calls++;
      if (calls > 1) throw StateError('Private clear error');
      return SharedPreferences.getInstance();
    }

    await mount(tester, SearchHistoryPage(preferencesLoader: loader));
    await tester.tap(find.byTooltip(t('history_clear')));
    await frames(tester);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, t('history_clear'))));
    await frames(tester);
    expect(find.text(t('ui_history_clear_failed')), findsOneWidget);
    expect(find.text(newest), findsOneWidget);
    expect(find.textContaining('Private'), findsNothing);
    await finish(tester);
  });
  testWidgets('history selection returns its exact query', (tester) async {
    String? selected;
    await mount(
        tester,
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      selected = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const SearchHistoryPage()));
                    },
                    child: const Text('Open history')))));
    await tester.tap(find.text('Open history'));
    await frames(tester);
    await tester.tap(find.text(newest));
    await frames(tester);
    expect(selected, newest);
    await finish(tester);
  });
  testWidgets('account history mounts the search tab before applying query',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'search_history': ['Camry']
    });
    await mount(tester, const HomePage());
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(5);
    await frames(tester);
    final history = find.text(t('account_search_history'));
    await tester.scrollUntilVisible(history, 350,
        scrollable: find
            .descendant(
                of: find.byType(AccountTab), matching: find.byType(Scrollable))
            .first,
        maxScrolls: 40);
    await frames(tester);
    await tester.tap(history);
    await frames(tester);
    expect(find.byType(SearchHistoryPage), findsOneWidget);
    await tester.tap(find.text('Camry'));
    await frames(tester);
    expect(find.byType(SearchTab), findsOneWidget);
    expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3);
    expect(tester.state<SearchTabState>(find.byType(SearchTab)).controller.text,
        'Camry');
    expect(
        requests.any((uri) =>
            uri.path.endsWith('/cars_public') &&
            uri.toString().toLowerCase().contains('camry')),
        isTrue);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('fines link failure stays localized without leaving the app',
      (tester) async {
    Uri? requested;
    await mount(tester, FinesPage(linkLauncher: (uri) async {
      requested = uri;
      return false;
    }));
    await tester.tap(find.text(t('fines_iraq')));
    await frames(tester);
    expect(requested.toString(), FinesPage.iraqFinesUrl);
    expect(find.text(t('fines_open_failed')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets(
      'settings serializes each pending preference without blocking the other',
      (tester) async {
    Completer<void>? gate;
    var calls = 0;
    Future<SharedPreferences> loader() async {
      calls++;
      await gate?.future;
      return SharedPreferences.getInstance();
    }

    await mount(tester, SettingsPage(preferencesLoader: loader));
    gate = Completer<void>();
    var switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    switches[0].onChanged!(false);
    await frames(tester);
    switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[0].onChanged, isNull);
    expect(switches[1].onChanged, isNotNull);
    switches[1].onChanged!(false);
    await frames(tester);
    expect(calls, 3);
    gate.complete();
    await frames(tester);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('motri.notifications.push'), isFalse);
    expect(prefs.getBool('motri.notifications.email'), isFalse);
    expect(
        tester
            .widgetList<Switch>(find.byType(Switch))
            .take(2)
            .every((w) => w.onChanged != null),
        isTrue);
    await finish(tester);
  });
  testWidgets('settings waits for stored preferences before allowing edits',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('motri.notifications.email', false);
    final gate = Completer<SharedPreferences>();
    await mount(tester, SettingsPage(preferencesLoader: () => gate.future));
    final pending = tester.widgetList<Switch>(find.byType(Switch)).take(2);
    expect(pending.every((w) => w.onChanged == null), isTrue);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    gate.complete(prefs);
    await frames(tester);
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches[1].value, isFalse);
    expect(switches.take(2).every((w) => w.onChanged != null), isTrue);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await finish(tester);
  });
}
