import '../l10n/app_locale.dart';
import '../l10n/app_strings.dart';

abstract final class JobTypes {
  static const keys = [
    'job_shift_full',
    'job_shift_part',
    'job_freelance',
    'job_remote'
  ];
  static String? keyFor(String value) {
    for (final key in keys) {
      if (key == value ||
          AppLocale.values
              .any((locale) => AppStrings.t(key, locale.code) == value)) {
        return key;
      }
    }
    return null;
  }

  static String label(String value) =>
      keyFor(value) == null ? value : t(keyFor(value)!);
  // Existing job rows use Arabic values. Keep persistence independent of UI locale.
  static String stored(String key) => AppStrings.t(key, 'ar');
}
