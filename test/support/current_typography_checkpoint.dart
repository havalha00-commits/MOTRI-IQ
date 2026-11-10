import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart' as app;
import 'package:motri_iq/l10n/app_locale.dart';

Future<void> currentTypographyCheckpoint(
    WidgetTester tester, String surface) async {
  if (!const bool.fromEnvironment('UI_CURRENT_TYPOGRAPHY_HOLD')) return;
  final locale = appLocale;
  if (!(locale == AppLocale.ar && !app.AppColors.isDark ||
      locale == AppLocale.ku && app.AppColors.isDark)) {
    return;
  }
  // The normal root uses these delegates, appearance and locale. Hold only
  // after each fixture's loaded-state assertions, without mutating real data.
  // ignore: avoid_print
  print('TYPOGRAPHY_${surface}_${locale.code.toUpperCase()}');
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(seconds: 12)));
}
