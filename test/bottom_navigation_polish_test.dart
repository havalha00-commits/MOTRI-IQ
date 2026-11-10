import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/ui/app_bottom_navigation.dart';
import 'support/current_typography_checkpoint.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    for (final font in {
      'MotriLatin': 'Inter',
      'MotriSans': 'Cairo',
      'MotriKurdish': 'NotoSansArabic'
    }.entries) {
      final loader = FontLoader(font.key);
      for (final weight in [
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold'
      ]) {
        loader
            .addFont(rootBundle.load('assets/fonts/${font.value}-$weight.ttf'));
      }
      await loader.load();
    }
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final width in [320.0, 390.0, 900.0]) {
        testWidgets('bottom navigation ${locale.code} dark=$dark width=$width',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize = Size(width, 844);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          final semantics = tester.ensureSemantics();

          var selected = 0;
          final visited = <int>[];
          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(2),
                    padding: const EdgeInsets.only(bottom: 34),
                    disableAnimations: true),
                child: child!),
            home: StatefulBuilder(
                builder: (context, setState) => Directionality(
                    textDirection: locale.direction,
                    child: Scaffold(
                      body: Center(child: Text(t('nav_home'))),
                      bottomNavigationBar: AppBottomNavigation(
                          selectedIndex: selected,
                          onSelected: (i) {
                            visited.add(i);
                            setState(() => selected = i);
                          }),
                    ))),
          ));
          await tester.pumpAndSettle();
          final destinations = find.byType(NavigationDestination);
          expect(destinations, findsNWidgets(6));
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          final scheme =
              Theme.of(tester.element(destinations.first)).colorScheme;
          expect(bar.indicatorColor, scheme.primary);
          expect(bar.labelTextStyle!.resolve({WidgetState.selected})!.color,
              dark ? scheme.onSurface : scheme.primary);
          final contrast = (scheme.onPrimary.computeLuminance() + .05) /
              (scheme.primary.computeLuminance() + .05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          final barRect = tester.getRect(find.byType(NavigationBar));
          expect(barRect.width, lessThanOrEqualTo(640));
          expect(barRect.height, greaterThanOrEqualTo(110));
          final first = tester.getCenter(destinations.first).dx;
          final last = tester.getCenter(destinations.last).dx;
          expect(first < last, locale == AppLocale.en);
          for (var i = 0; i < 6; i++) {
            expect(tester.getSize(destinations.at(i)).width,
                greaterThanOrEqualTo(48));
            final destination =
                tester.widget<NavigationDestination>(destinations.at(i));
            expect(destination.tooltip, destination.label);
            final label = find.descendant(
                of: destinations.at(i), matching: find.text(destination.label));
            expect(tester.getSize(label).height, lessThanOrEqualTo(22),
                reason:
                    '${destination.label} stays on one line at ${locale.code} width=$width');
            final labelRect = tester.getRect(label);
            final slotRect = tester.getRect(destinations.at(i));
            expect(labelRect.left, greaterThanOrEqualTo(slotRect.left));
            expect(labelRect.right, lessThanOrEqualTo(slotRect.right));
            await tester.tap(destinations.at(i));
            await tester.pumpAndSettle();
            expect(
                tester
                    .widget<NavigationBar>(find.byType(NavigationBar))
                    .selectedIndex,
                i);
            expect(
                tester
                    .getSemantics(destinations.at(i))
                    .getSemanticsData()
                    .flagsCollection
                    .isSelected,
                ui.Tristate.isTrue);
            expect(tester.takeException(), isNull);
          }
          expect(visited, [0, 1, 2, 3, 4, 5]);
          await tester.tap(destinations.first);
          await tester.pumpAndSettle();
          if (width == 390) {
            await currentTypographyCheckpoint(tester, 'BOTTOM_NAV');
          }
          semantics.dispose();
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
