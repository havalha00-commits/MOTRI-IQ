import '../l10n/app_strings.dart';
import '../l10n/app_locale.dart';

/// UI labels change with locale; selection IDs and stored values do not.
class BusinessCategories {
  static const keys = [
    'svc_showrooms',
    'svc_parts',
    'svc_mechanic',
    'svc_tires',
    'svc_batteries',
    'svc_wash_polish',
    'svc_oils_filters',
    'svc_accessories',
    'svc_insurance',
    'svc_towing',
    'svc_dealers',
    'svc_car',
    'common_other'
  ];
  static String? keyFor(String value) {
    for (final key in keys) {
      if (value == key ||
          AppStrings.supported
              .any((locale) => AppStrings.t(key, locale) == value)) {
        return key;
      }
    }
    for (final alias in const {
      'svc_maintenance': 'svc_mechanic',
      'svc_oils': 'svc_oils_filters'
    }.entries) {
      if (value == alias.key ||
          AppStrings.supported
              .any((locale) => AppStrings.t(alias.key, locale) == value)) {
        return alias.value;
      }
    }
    return null;
  }

  static String storedValue(String value) {
    final key = keyFor(value);
    return key == null ? value : AppStrings.t(key, 'ar');
  }

  static List<String> get storedValues =>
      [for (final key in keys) AppStrings.t(key, 'ar')];
  static String label(String value) {
    final key = keyFor(value);
    return key == null ? value : t(key);
  }

  static List<String> queryValues(String value) {
    if (value.isEmpty ||
        value == 'common_all' ||
        AppStrings.supported
            .any((locale) => AppStrings.t('common_all', locale) == value)) {
      return [];
    }
    final key = keyFor(value);
    if (key == null) return [value];
    return <String>{
      for (final locale in AppStrings.supported) AppStrings.t(key, locale),
      if (key == 'svc_mechanic')
        for (final locale in AppStrings.supported)
          AppStrings.t('svc_maintenance', locale),
      if (key == 'svc_oils_filters')
        for (final locale in AppStrings.supported)
          AppStrings.t('svc_oils', locale),
    }.toList();
  }
}
