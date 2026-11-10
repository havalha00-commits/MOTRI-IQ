// إعادة إنتاج وإثبات سبب خطأ "No MaterialLocalizations found".
//
// الاختبار يبني `MaterialApp` بنفس سطرَي `locale` و`localizationsDelegates`
// المستخدمين في `MotriIqApp` حرفيًا، ثم يعرض `RefreshIndicator` و`NavigationBar`
// — وهما العنصران المذكوران في رسالة الخطأ.
//
// الاختبار فاشل قبل الإصلاح (يبلّغ عن الخطأ بدل إخفائه)، ويمرّ بعد الإصلاح.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';

/// نفس بناء `MaterialApp` في `MotriIqApp`، مع إبقاء اختيار اللغة متاحًا
/// للاختبار بدل قراءة `ValueNotifier` مباشرة.
Widget appUnderTest(AppLocale locale) => MaterialApp(
      debugShowCheckedModeBanner: false,
      // سطر الإنتاج بعد الإصلاح: اللغة الحقيقية بلا تحوير.
      locale: locale.locale,
      supportedLocales: const <Locale>[
        Locale('ar'),
        Locale('ku'),
        Locale('en'),
      ],
      localizationsDelegates: appLocalizationsDelegates,
      builder: (BuildContext context, Widget? child) => AppStringsScope(
        locale: locale,
        child: child ?? const SizedBox.shrink(),
      ),
      home: Directionality(
        textDirection: locale.direction,
        child: Scaffold(
          body: RefreshIndicator(
            onRefresh: () async {},
            child: ListView(
              children: const <Widget>[SizedBox(height: 400)],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: 0,
            destinations: const <NavigationDestination>[
              NavigationDestination(icon: Icon(Icons.home), label: 'الرئيسية'),
              NavigationDestination(icon: Icon(Icons.search), label: 'البحث'),
            ],
          ),
        ),
      ),
    );

void main() {
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);

  for (final AppLocale locale in AppLocale.values) {
    testWidgets('${locale.code} — MaterialLocalizations متاح', (tester) async {
      await tester.pumpWidget(appUnderTest(locale));
      await tester.pump();

      // وجود الـancestor هو جوهر المشكلة، لا مجرد عدم وجود استثناء.
      final BuildContext ctx = tester.element(find.byType(NavigationBar));
      expect(Localizations.of<MaterialLocalizations>(ctx, MaterialLocalizations),
          isNotNull,
          reason: 'لا MaterialLocalizations للغة ${locale.code}');

      expect(tester.takeException(), isNull,
          reason: 'خطأ MaterialLocalizations مع ${locale.code}');
    });
  }

  testWidgets('الكردية ترث Material widgets من MaterialApp واحد',
      (tester) async {
    await tester.pumpWidget(
        appUnderTest(AppLocale.ku));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // لاMaterialApp ثانٍ داخل المحتوى.
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  test('لغة لا تدعمها Material تعيد لغة نص يدعمها', () {
    // Flutter لا يشحن ترجمة Material للكردية، فواجهة Material تستعمل
    // العربية — وهي اللغة الصحيحة لحرف السوراني.
    expect(AppLocale.ku.materialLocale.languageCode, 'ar');
    expect(AppLocale.ku.code, 'ku',
        reason: 'لغة التطبيق تبقى كردية ولا تُغلق');
    expect(AppLocale.ar.materialLocale.languageCode, 'ar');
    expect(AppLocale.en.materialLocale.languageCode, 'en');
  });

  test('كل اللغات تمرّ بلغة Material مدعومة', () {
    const Set<String> supported = <String>{
      'ar',
      'en',
    };
    for (final AppLocale locale in AppLocale.values) {
      expect(supported.contains(locale.materialLocale.languageCode), isTrue,
          reason: '${locale.code} تمرر لغة غير مدعومة');
    }
  });
}
