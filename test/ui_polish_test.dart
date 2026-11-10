import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test-publishable-key');
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });

  Widget host(Widget page, AppLocale locale, TargetPlatform platform,
          {double scale = 1}) =>
      MaterialApp(
        key: UniqueKey(),
        theme: buildAppTheme(Brightness.light).copyWith(platform: platform),
        locale: locale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        builder: (context, child) => AppStringsScope(
            locale: locale,
            child: MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!)),
        home: page,
      );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final locale in AppLocale.values) {
      for (final page in <String, Widget>{
        'settings': const SettingsPage(),
        'support': const SupportCenterPage(),
        'fines': const FinesPage(),
        'guest': const HomePage(),
        'account': const Scaffold(body: AccountTab()),
        'search': const Scaffold(body: SearchTab()),
        'details': CarDetailsPage(car: const {
          'id': 'ui-polish-car',
          'brand': 'Toyota',
          'model': 'Land Cruiser',
          'year': 2025,
          'price': 45000,
          'seller_phone': '07701234567',
          'description': 'وصف السيارة',
          'province': 'بغداد',
        }),
      }.entries) {
        testWidgets(
            '${platform.name} ${locale.code} ${page.key}: direction and large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          tester.view.physicalSize = const Size(360, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester
              .pumpWidget(host(page.value, locale, platform, scale: 1.3));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);
          final pageContext =
              tester.element(find.byType(page.value.runtimeType));
          final scaffold = find.byType(Scaffold).first;
          expect(Directionality.of(tester.element(scaffold)), locale.direction);
          expect(Directionality.of(pageContext), locale.direction);
          // A forward disclosure uses a right-chevron in LTR; Flutter mirrors it in RTL.
          expect(find.byIcon(Icons.chevron_left), findsNothing);
          if (page.key != 'settings') {
            expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
          }
          if (page.key == 'settings') {
            await tester.scrollUntilVisible(find.text(t('settings_about')), 200,
                scrollable: find.byType(Scrollable).first);
            await tester.pump();
            final label = tester.getCenter(find.text(t('settings_about')));
            final aboutTile = find.ancestor(
                of: find.text(t('settings_about')), matching: find.byType(ListTile));
            final arrow = tester.getCenter(find.descendant(
                of: aboutTile, matching: find.byIcon(Icons.chevron_right_rounded)));
            expect(
                locale.direction == TextDirection.rtl
                    ? arrow.dx < label.dx
                    : arrow.dx > label.dx,
                isTrue,
                reason: 'Disclosure must align at the trailing edge');
          }
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      }
    }
  }

  testWidgets('guest can change language and open settings without signing in',
      (tester) async {
    await tester.pumpWidget(
        host(const HomePage(), AppLocale.ar, TargetPlatform.android));
    await tester.pump();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    nav.onDestinationSelected!(5);
    await tester.pump();
    expect(find.byTooltip(t('account_language')), findsOneWidget);
    await tester.tap(find.byTooltip(t('settings_title')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('notification choices survive leaving and reopening settings',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
        host(const SettingsPage(), AppLocale.ar, TargetPlatform.android));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
        (await SharedPreferences.getInstance())
            .getBool('motri.notifications.push'),
        isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
        host(const SettingsPage(), AppLocale.ar, TargetPlatform.android));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'missing external destination reports failure without breaking UI',
      (tester) async {
    await tester.pumpWidget(host(
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => openExternalLink(context, null),
                    child: const Text('Open')))),
        AppLocale.ar,
        TargetPlatform.android));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Open'));
    await tester.pump();
    expect(find.text(t('fines_open_failed')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
