import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/ui/language_picker_sheet.dart';
import 'support/current_typography_checkpoint.dart';

void main() {
  setUpAll(() async {
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
  for (final short in [false, true]) {
    for (final locale in AppLocale.values) {
      for (final dark in [false, true]) {
        testWidgets(
            'Language sheet ${locale.code} dark=$dark short=$short enlarged',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            tester.view.physicalSize =
                short ? const Size(568, 320) : const Size(320, 720);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
          }
          AppLocale? result;
          Future<void> frames() async {
            for (var i = 0; i < 20; i++) {
              await tester.pump(const Duration(milliseconds: 20));
            }
          }

          await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            locale: locale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(short ? 2 : 1.6)),
                child: child!),
            home: Scaffold(
                body: Builder(
                    builder: (context) => Center(
                        child: TextButton(
                            onPressed: () async {
                              result = await showModalBottomSheet<AppLocale>(
                                  context: context,
                                  useSafeArea: true,
                                  showDragHandle: true,
                                  builder: (_) =>
                                      LanguagePickerSheet(selected: locale));
                            },
                            child: const Text('Open language'))))),
          ));
          await frames();
          await tester.tap(find.text('Open language'));
          await frames();
          expect(tester.takeException(), isNull);
          expect(find.byType(RadioListTile<AppLocale>), findsNWidgets(3));
          final tile = tester.widget<RadioListTile<AppLocale>>(
              find.byType(RadioListTile<AppLocale>).first);
          final selectedColor =
              tile.fillColor!.resolve({WidgetState.selected})!;
          final surface =
              Theme.of(tester.element(find.byType(LanguagePickerSheet)))
                  .colorScheme
                  .surface;
          final a = selectedColor.computeLuminance();
          final b = surface.computeLuminance();
          expect(((a > b ? a : b) + .05) / ((a < b ? a : b) + .05),
              greaterThanOrEqualTo(3),
              reason: 'Selection must stand out from the sheet');
          if (!short) {
            await currentTypographyCheckpoint(tester, 'LANGUAGE_SHEET');
          }
          final choice = AppLocale.values.last;
          await tester.ensureVisible(find.text(choice.label));
          await frames();
          await tester.tap(find.text(choice.label));
          await frames();
          expect(result, choice);
          await tester.tap(find.text('Open language'));
          await frames();
          final context = tester.element(find.byType(LanguagePickerSheet));
          await tester.tap(find
              .byTooltip(MaterialLocalizations.of(context).closeButtonTooltip));
          await frames();
          expect(result, isNull);
          expect(find.byType(LanguagePickerSheet), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await frames();
        });
      }
    }
  }
}
