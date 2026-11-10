/// طبقة الوصل بين `MaterialApp` وجدول النصوص `AppStrings`.
///
/// لماذا هذه الطبقة موجودة
/// -----------------------
///
/// كان الحلّ السابق تمرير `Locale('ar')` إلى `MaterialApp` عند اختيار
/// الكردية، لأن Flutter لا يشحن ترجمة `MaterialLocalizations` للسوراني
/// (`kMaterialSupportedLanguages` فيه `ar` ولا `ku`). لكن ذلك يخلق
/// عيبًا أخطر: `MaterialApp.locale` لا يتغيّر بين العربية والكردية، فلا
/// يعيد `Localizations` تحميل الـdelegates، فلا تُعاد بناء أي route داخل
/// `Navigator` — ويبقى نص الواجهة عربيًا مهما غيّر `t()` قيمته.
///
/// الحل هنا بطبقتَين:
///
///   * `MaterialApp.locale` صار `Locale('ku')` فعليًا، فتتغيّر قيمة
///     `Localizations` ويتغيّر ناتج `updateShouldNotify` فتُعاد بناء الشجرة
///     كلها — وهذا ما يجعل `t()` يُقرأ من جديد في كل مكان.
///   * النصوص التي لا نملك لها ترجمة سورانية تُخدَم بتفويض صريح إلى
///     `ar`: نصوص واجهة Material نفسها (Material/Widgets/Cupertino)، وهي
///     عربية الحرف أصلًا.
library;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_locale.dart';
import 'app_strings.dart';

/// نطاق اللغة يُثبَّت فوق `Navigator`، فيصل إلى كل route يفتحه التطبيق.
///
/// لماذا نحتاجه صراحةً
/// -------------------
///
/// `MaterialApp.locale` صار `Locale('ku')` فعليًا، وهذا يُصلح `Localizations`
/// و`MaterialLocalizations`. لكنه **لا يكفي** وحده لإظهار النصوص المترجَمة:
///
/// استدعاء `t('key')` ينفَّذ داخل `build()` لأي عنصر أب — مثل
/// `HomeShell` الذي يبني شريط التنقّل —، وقد لا يكون ذلك الأب مسجّلًا
/// اعتماده على `Localizations`. فحتى لو تغيّرت `Localizations`، لا يُعلَّم
/// الأب rebuilding، وتبقى النصوص القديمة معروضة.
///
/// الحل: أي `build` يستدعي `t()` يصرّح باعتماده عبر
/// [BuildContext.dependOnAppStrings]، فالنطاق يتغيّر ويُعلّم هذا `build`
/// تحديدًا لإعادة البناء.
class AppStringsScope extends InheritedWidget {
  const AppStringsScope({
    required this.locale,
    required super.child,
    super.key,
  });

  final AppLocale locale;

  /// يقرأ اللغة مع تسجيل اعتماد، فيُعاد بناء المستدعي عند تغيّرها.
  static AppLocale read(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppStringsScope>()?.locale ??
      appLocale;

  @override
  bool updateShouldNotify(AppStringsScope oldWidget) =>
      oldWidget.locale != locale;
}

extension AppStringsDependency on BuildContext {
  /// يجب استدعاؤه في أول `build` يستخدم [t]، وإلا بقي النص معروضًا
  /// باللغة القديمة بعد التبديل.
  AppLocale dependOnAppStrings() => AppStringsScope.read(this);
}

/// اللغة التي تُمرَّر إلى `MaterialApp.locale` كما هي، بلا تحوير.
extension AppLocaleLocale on AppLocale {
  Locale get locale => Locale(code);
}

/// نصوص التطبيق للغة معيّنة، تُحمَّل عبر `Localizations`.
///
/// تُعرِّف `==` حسب اللغة فقط، وهي الآلية التي تجعل `Localizations` تعيد
/// بناء كل المعتمدين عند اختلاف اللغة.
@immutable
class AppStringsLocale {
  const AppStringsLocale(this.code);

  final String code;

  String t(String key) => AppStrings.t(key, code);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppStringsLocale && other.code == code);

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'AppStringsLocale($code)';
}

/// يقرأ نصوص التطبيق من `context` بدل الحالة العامة.
extension AppStringsContext on BuildContext {
  AppStringsLocale get strings =>
      Localizations.of<AppStringsLocale>(this, AppStringsLocale) ??
      AppStringsLocale(appLocale.code);
}

/// يوفّر [AppStringsLocale] لكل اللغات الثلاث.
class AppStringsDelegate extends LocalizationsDelegate<AppStringsLocale> {
  const AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == 'ar' ||
      locale.languageCode == 'ku' ||
      locale.languageCode == 'en';

  @override
  Future<AppStringsLocale> load(Locale locale) async =>
      AppStringsLocale(locale.languageCode);

  @override
  bool shouldReload(AppStringsDelegate old) => false;
}

/// يخدم نصوص واجهة Material للسوراني من العربية.
class AppLocaleMaterialDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const AppLocaleMaterialDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('ar'));

  @override
  bool shouldReload(AppLocaleMaterialDelegate old) => false;
}

/// نفس الفكرة لنصوص `Widgets` (مثل `SemanticsService` والـtooltips).
class AppLocaleWidgetsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  const AppLocaleWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('ar'));

  @override
  bool shouldReload(AppLocaleWidgetsDelegate old) => false;
}

/// ونصوص `Cupertino` كذلك.
class AppLocaleCupertinoDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const AppLocaleCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ku';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('ar'));

  @override
  bool shouldReload(AppLocaleCupertinoDelegate old) => false;
}

/// قائمة الـdelegates الكاملة لـ`MaterialApp` — تُستعمل كما هي في الإنتاج
/// وفي الاختبار حتى لا يختلفا.
const List<LocalizationsDelegate<Object?>> appLocalizationsDelegates =
    <LocalizationsDelegate<Object?>>[
  AppStringsDelegate(),
  AppLocaleMaterialDelegate(),
  AppLocaleWidgetsDelegate(),
  AppLocaleCupertinoDelegate(),
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];