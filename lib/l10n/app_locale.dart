/// إدارة لغة الواجهة وحفظها.
///
/// تسير على النمط نفسه الذي يستعمله `setDarkMode` في `main.dart`: تغيير
/// الحالة العامة أولًا ثم إشعار `MaterialApp`، فالشجرة تعيد البناء وتقرأ
/// قيمة واحدة متسقة.
///
/// العربية هي الافتراضية وما بُني عليه التطبيق، لذلك أي اختيار غير معروف
/// يعود إليها — لا يمكن أن يختفي النص العربي بسبب خطأ في التخزين.
library;

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_strings.dart';

const String kLocalePref = 'motri.locale';

/// لُغات الواجهة المتاحة واتجاه كل منها.
///
/// الكردية (سوراني) تكتب بحرف عربي وتُقرأ من اليمين لليسار مثل العربية،
/// أما الإنجليزية فتسار من اليسار لليمين.
enum AppLocale {
  ar('ar', 'العربية', TextDirection.rtl),
  ku('ku', 'کوردی', TextDirection.rtl),
  en('en', 'English', TextDirection.ltr);

  const AppLocale(this.code, this.label, this.direction);

  final String code;
  final String label;
  final TextDirection direction;

  /// اللغة التي تُمرَّر إلى `MaterialApp.locale`.
  ///
  /// تختلف عن [code] في الكردة فقط: Flutter لا يشحن ترجمة
  /// `MaterialLocalizations` للكردية — `kMaterialSupportedLanguages` يحتوي
  /// `ar` ولا يحتوي `ku` — فيُتخطّى الـdelegate عند `Locale('ku')` ولا يبقى
  ///ancestor لـ`MaterialLocalizations`، فيرمي `RefreshIndicator` و
  /// `NavigationBar` خلف `No MaterialLocalizations found`.
  ///
  /// السوراني تُكتب بحرف عربي من اليمين لليسار، فترجمة Material العربية
  /// هي اللغة الصحيحة لنصوص واجهة Material عندها، والاتجاه يبقى RTL.
  Locale get materialLocale => switch (this) {
        AppLocale.ar => const Locale('ar'),
        AppLocale.ku => const Locale('ar'),
        AppLocale.en => const Locale('en'),
      };

  static AppLocale fromCode(String? code) {
    for (final AppLocale value in AppLocale.values) {
      if (value.code == code) return value;
    }
    return AppLocale.ar;
  }
}

/// اللغة النشطة الآن. تُقرأ في `build` داخل `MaterialApp` فتُعيد الشجرة
/// بناء نفسها بالكامل عند التبديل.
final ValueNotifier<AppLocale> appLocaleNotifier =
    ValueNotifier<AppLocale>(AppLocale.ar);

AppLocale get appLocale => appLocaleNotifier.value;

/// يبدّل لغة الواجهة ويحفظها، ويحدّث اتجاه الواجهة تبعًا لها.
///
/// العربية RTL والإنجليزية LTR — لا يتغير اتجاه أي منهما.
Future<void> setAppLocale(AppLocale locale) async {
  if (appLocale == locale) return;
  appLocaleNotifier.value = locale;
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(kLocalePref, locale.code);
  } catch (_) {
    // تعذّر الحفظ لا يمنع التبديل في الجلسة الحالية.
  }
}

/// يقرأ اللغة المحفوظة قبل `runApp`، وإلا لم يُطبَّق الاختيار بعد إعادة
/// فتح التطبيق.
Future<void> loadAppLocale() async {
  try {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    appLocaleNotifier.value =
        AppLocale.fromCode(prefs.getString(kLocalePref));
  } catch (_) {
    // لا مخزن تفضيلات: تبقى العربية.
  }
}

/// اختصار للنص المترجَم حسب اللغة النشطة.
String t(String key) => AppStrings.t(key, appLocaleNotifier.value.code);
