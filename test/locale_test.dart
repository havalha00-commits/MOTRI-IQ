// اختبارات لغة الواجهة (الكردية + العربية + الإنجليزية).
//
// الهدف تثبيت ثلاثة أمور: أن العربية لم تتغير حرفًا، وأن الكردية تُبدَّل
// فعلًا وتبقى RTL، وأن الاختيار يُحفظ ويُستعاد بعد إعادة فتح التطبيق.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_strings.dart';

void main() {
  setUpAll(() async {
    // نظام اللغة مستقل تمامًا عن Supabase، فلا حاجة لتهيئة عميل هنا.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
  });

  group('اللغات والاتجاه', () {
    test('العربية هي الافتراضية', () {
      expect(AppLocale.ar.code, 'ar');
      expect(appLocale, AppLocale.ar);
    });

    test('اتجاه كل لغة صحيح: الكردية RTL والإنجليزية LTR', () {
      expect(AppLocale.ar.direction, TextDirection.rtl);
      expect(AppLocale.ku.direction, TextDirection.rtl,
          reason: 'السوراني تُكتب من اليمين لليسار');
      expect(AppLocale.en.direction, TextDirection.ltr);
    });

    test('لغة غير معروفة ترجع للعربية ولا تُفقد النص', () {
      expect(AppLocale.fromCode('fr'), AppLocale.ar);
      expect(AppLocale.fromCode(null), AppLocale.ar);
      expect(AppLocale.fromCode(''), AppLocale.ar);
    });
  });

  group('جدول النصوص', () {
    test('كل مفتاح كردي له مقابل عربي — لا مفتاح يتعطل', () {
      for (final String key in AppStrings.ku.keys) {
        expect(AppStrings.ar.containsKey(key), isTrue,
            reason: 'المفتاح «$key» مكردي بلا قيمة عربية');
      }
    });

    test('العربية تُعاد كما هي بلا مساس', () {
      expect(AppStrings.t('nav_home', 'ar'), 'الرئيسية');
      expect(AppStrings.t('account_language', 'ar'), 'اللغة');
      expect(AppStrings.t('lang_kurdish', 'ar'), 'الكردية');
    });

    test('الكردية تُترجم فعلًا وتختلف عن العربية', () {
      expect(AppStrings.t('nav_home', 'ku'), 'سەرەکی');
      expect(AppStrings.t('lang_kurdish', 'ku'), 'کوردی');
      expect(AppStrings.t('account_language', 'ku'), 'زمان');
      expect(AppStrings.t('nav_home', 'ku'), isNot(AppStrings.t('nav_home', 'ar')));
    });

    test('مفتاح غير موجود لا يعود إلى العربية في الكردية', () {
      // العقد الجديد: عند اختيار الكردية لا يجوز الرجوع إلى العربية.
      // المفتاح الغائب يُعاد كما هو (ويلقي خطأ في وضع الاختبار).
      expect(
        () => AppStrings.t('does_not_exist', 'ku'),
        throwsA(isA<AssertionError>()),
        reason: 'نص كردي ناقص يجب أن يُبلّغ فورًا لا أن يسقط بصمت للعربية',
      );
      // كل مفاتيح الكردية المستعملة لها نص.
      expect(AppStrings.t('account_chat', 'ku'), isNotEmpty);
    });

    test('الإنجليزية تُترجم فعلًا وتختلف عن العربية', () {
      expect(AppStrings.t('nav_home', 'en'), 'Home');
      expect(AppStrings.t('account_language', 'en'), 'Language');
      expect(AppStrings.t('lang_kurdish', 'en'), 'Kurdish');
      expect(AppStrings.t('nav_home', 'en'), isNot(AppStrings.t('nav_home', 'ar')));
    });

    test('كل مفتاح إنجليزي له مقابل عربي — لا مفتاح يتعطل', () {
      for (final String key in AppStrings.en.keys) {
        expect(AppStrings.ar.containsKey(key), isTrue,
            reason: 'المفتاح «$key» إنجليزي بلا قيمة عربية');
      }
    });

    test('مفتاح غير موجود لا يعود إلى العربية في الإنجليزية', () {
      expect(
        () => AppStrings.t('does_not_exist', 'en'),
        throwsA(isA<AssertionError>()),
        reason: 'نص إنجليزي ناقص يجب أن يُبلّغ فورًا لا أن يسقط بصمت للعربية',
      );
      expect(AppStrings.t('account_chat', 'en'), isNotEmpty);
    });

    test('النصوص الإنجليزية لا تحمل حروفًا عربية', () {
      final RegExp arabic = RegExp(r'[\u0600-\u06FF]');
      // استثناء ما هو ليس نص واجهة: رموز العملات وأسماء العلامات.
      const Set<String> allowed = <String>{
        'MOTRI IQ',
      };
      for (final MapEntry<String, String> entry in AppStrings.en.entries) {
        if (allowed.contains(entry.value.trim())) continue;
        expect(arabic.hasMatch(entry.value), isFalse,
            reason: 'النص الإنجليزي للمفتاح «${entry.key}» يحمل حروفًا عربية: '
                '"${entry.value}"');
      }
    });
  });

  group('الحفظ والاستعادة', () {
    test('setAppLocale يبدّل الحالة ويحفظها', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await setAppLocale(AppLocale.ku);
      expect(appLocale, AppLocale.ku);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kLocalePref), 'ku');

      await setAppLocale(AppLocale.ar);
      expect(appLocale, AppLocale.ar);
      expect(prefs.getString(kLocalePref), 'ar');
    });

    test('loadAppLocale يستعيد الاختيار المحفوظ', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kLocalePref: 'ku',
      });
      await loadAppLocale();
      expect(appLocale, AppLocale.ku,
          reason: 'لغة Kurdistan يجب أن تبقى بعد إعادة فتح التطبيق');
    });

    test('لا اختيار محفوظ = عربية', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await loadAppLocale();
      expect(appLocale, AppLocale.ar);
    });

    test('قيمة تالفة في التخزين ترجع للعربية بأمان', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kLocalePref: 'not-a-locale',
      });
      await loadAppLocale();
      expect(appLocale, AppLocale.ar);
    });
  });

  group('الاختصار t()', () {
    test('يتبع اللغة النشطة', () {
      appLocaleNotifier.value = AppLocale.ar;
      expect(t('nav_search'), 'البحث');
      appLocaleNotifier.value = AppLocale.ku;
      expect(t('nav_search'), 'گەڕان');
    });
  });
}
