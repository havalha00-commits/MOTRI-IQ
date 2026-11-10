import 'support/current_typography_checkpoint.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/ui/policy_document.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  String? shared;
  var shareFails = false;
  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  setUp(() {
    shared = null;
    shareFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, (call) async {
      if (shareFails) throw PlatformException(code: 'fixture-only');
      shared = (call.arguments as Map)['text'] as String?;
      return 'dev.fluttercommunity.plus/share/unavailable';
    });
  });
  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
  });
  final pages = <String, Widget Function()>{
    'support': () => const SupportCenterPage(),
    'about': () => AboutPage(
        infoLoader: () async => PackageInfo(
            appName: 'MOTRI IQ',
            packageName: 'com.motriiq.app',
            version: '1.2.3',
            buildNumber: '12345678901234567890')),
    'privacy': () => const PrivacyPolicyPage(),
    'terms': () => const TermsOfUsePage(),
  };
  Future<void> mount(WidgetTester tester, Widget page,
      {Brightness brightness = Brightness.light, double keyboard = 0}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    AppColors.isDark = brightness == Brightness.dark;
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(brightness),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => AppStringsScope(
                locale: locale,
                child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        textScaler: const TextScaler.linear(1.6),
                        viewInsets: keyboard == 0 ||
                                const bool.fromEnvironment('NATIVE_VIEWPORT')
                            ? MediaQuery.of(context).viewInsets
                            : EdgeInsets.only(bottom: keyboard)),
                    child: child!)),
            home: page)));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
  }

  Finder option(String key) =>
      find.ancestor(of: find.text(t(key)), matching: find.byType(ListTile));
  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 250,
        scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final brightness in Brightness.values) {
      for (final entry in pages.entries) {
        testWidgets('${locale.code} ${entry.key} $brightness large text',
            (tester) async {
          appLocaleNotifier.value = locale;
          await mount(tester, entry.value(), brightness: brightness);
          expect(tester.takeException(), isNull);
          if (entry.key == 'privacy' || entry.key == 'terms') {
            final document =
                tester.widget<PolicyDocument>(find.byType(PolicyDocument));
            expect(document.sections.length, entry.key == 'privacy' ? 10 : 11);
            expect(
                find.text(
                    '${t('terms_last_updated')}: ${t('about_last_updated_date')}'),
                findsOneWidget);
            expect(find.byType(SelectionArea), findsOneWidget);
          }
          await currentTypographyCheckpoint(tester, entry.key.toUpperCase());
          if ((const bool.fromEnvironment('UI_SUPPORT_LEGAL_REVIEW_HOLD') ||
                  (const bool.fromEnvironment('UI_SUPPORT_ONLY_REVIEW_HOLD') &&
                      entry.key == 'support')) &&
              locale == AppLocale.en &&
              brightness == Brightness.dark) {
            debugPrint('UI_${entry.key.toUpperCase()}_REVIEW_READY');
            await Future<void>.delayed(const Duration(seconds: 15));
          }
          if (entry.key == 'privacy' || entry.key == 'terms') {
            final footer = find.text(
                '${t('terms_last_updated')}: ${t('about_last_updated_date')}');
            await tester.ensureVisible(footer);
            await frames(tester);
            expect(footer.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          }
          await finish(tester);
        });
      }
    }
    testWidgets('${locale.code} support contact sheet wraps and cancels',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester, const SupportCenterPage(),
          brightness:
              locale == AppLocale.ku ? Brightness.dark : Brightness.light);
      await reveal(tester, option('support_contact'));
      await tester.tap(option('support_contact'));
      await frames(tester);
      expect(find.text(kSupportPhone), findsOneWidget);
      expect(find.text(t('settings_call')), findsOneWidget);
      expect(find.text(t('contact_whatsapp')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await currentTypographyCheckpoint(tester, 'SUPPORT_CONTACT');
      Navigator.of(tester.element(find.text(kSupportPhone))).pop();
      await frames(tester);
      await finish(tester);
    });
    testWidgets('${locale.code} report category keyboard and cancellation',
        (tester) async {
      appLocaleNotifier.value = locale;
      await mount(tester, const SupportCenterPage(),
          keyboard: 220,
          brightness:
              locale == AppLocale.ku ? Brightness.dark : Brightness.light);
      await reveal(tester, option('support_report_problem'));
      await tester.tap(option('support_report_problem'));
      await frames(tester);
      expect(find.byType(RadioGroup<String>), findsOneWidget);
      final category = find.text(t('support_issue_account'));
      await tester.scrollUntilVisible(category, 150,
          scrollable: find
              .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Scrollable))
              .first);
      await tester.tap(category);
      await tester.ensureVisible(find.byType(TextField));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'A draft support request');
      if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)));
      }
      await frames(tester);
      expect(tester.widget<TextField>(find.byType(TextField)).textDirection,
          TextDirection.ltr);
      expect(tester.takeException(), isNull);
      final keyboard = const bool.fromEnvironment('NATIVE_VIEWPORT')
          ? tester.view.viewInsets.bottom / tester.view.devicePixelRatio
          : 220.0;
      expect(keyboard, greaterThan(0));
      await Scrollable.ensureVisible(tester.element(find.byType(TextField)),
          alignment: .9);
      await frames(tester);
      expect(
          tester.getBottomRight(find.byType(TextField)).dy,
          lessThanOrEqualTo(
              tester.getTopLeft(find.text(t('common_cancel'))).dy + 1));
      expect(
          tester.getBottomRight(find.text(t('common_cancel'))).dy,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
                  keyboard));
      await currentTypographyCheckpoint(tester, 'SUPPORT_REPORT');
      await tester.tap(find.text(t('common_cancel')));
      await frames(tester);
      expect(shared, isNull);
      expect(tester.takeException(), isNull);
      await finish(tester);
    });
  }
  testWidgets('report includes selected category and real line breaks',
      (tester) async {
    appLocaleNotifier.value = AppLocale.en;
    await mount(tester, const SupportCenterPage());
    await reveal(tester, option('support_report_problem'));
    await tester.tap(option('support_report_problem'));
    await frames(tester);
    final category = find.text(t('support_issue_account'));
    await tester.scrollUntilVisible(category, 150,
        scrollable: find
            .descendant(
                of: find.byType(AlertDialog), matching: find.byType(Scrollable))
            .first);
    await tester.tap(category);
    await frames(tester);
    final field = find.byType(TextField);
    await tester.ensureVisible(field);
    await tester.enterText(field, 'Details for support');
    await tester.tap(find.text(t('misc_follow')));
    await frames(tester);
    expect(shared, contains(t('support_issue_account')));
    expect(shared, contains('Details for support'));
    expect(shared, contains('\n'));
    expect(shared, isNot(contains(r'\n')));
    expect(tester.takeException(), isNull);
    await finish(tester);
  });
  testWidgets('report share failure stays localized and can reopen',
      (tester) async {
    shareFails = true;
    await mount(tester, const SupportCenterPage());
    await reveal(tester, option('support_report_problem'));
    await tester.tap(option('support_report_problem'));
    await frames(tester);
    await tester.tap(find.text(t('misc_follow')));
    await frames(tester);
    expect(find.text(t('ui_support_share_failed')), findsOneWidget);
    await tester.tap(option('support_report_problem'));
    await frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    await finish(tester);
  });
}
