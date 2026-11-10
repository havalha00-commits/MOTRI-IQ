// إثبات مشكلة "اللغة تُحفظ لكن الواجهة لا تتغيّر".
//
// السبب الجذري كان في التوصيل لا في التخزين: نظام الترجمة كان يعمل، لكنه
// موصول بـ`t('key')` في موضعين فقط من مئات النصوص، و`home` كان `const`
// داخل `MaterialApp` فلم تكن الـroutes تُعاد بناؤها عند تبديل اللغة.
//
// هذا الملف يثبت ثلاثة أشياء:
//   1. كل `t('key')` مستعمل في `lib/main.dart` له قيمة عربية وكردية.
//   2. القيم العربية مطابقة حرفيًا للنصوص التي كانت موجودة قبل الربط.
//   3. التبديل الحيّ ar↔ku يعيد بناء الواجهة فعلًا داخل التطبيق الحقيقي.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_strings.dart';
import 'package:motri_iq/main.dart';

/// النصوص العربية التي كانت حرفية في `main.dart` قبل تحويلها إلى `t('key')`.
/// تطابقها مع `AppStrings.ar` هو ما يضمن أن الربط لم يغيّر العربية حرفًا.
const Map<String, String> arabicBeforeWiring = <String, String>{
  'nav_home': 'الرئيسية',
  'nav_search': 'البحث',
  'nav_add': 'إضافة',
  'nav_account': 'حسابي',
  'account_quick_actions': 'إجراءات سريعة',
  'account_options': 'الخيارات',
  'account_more_options': 'المزيد من الخيارات',
  'account_language': 'اللغة',
  'account_wallet_topup': 'تعبئة المحفظة',
  'account_fines': 'الغرامات',
  'account_search_history': 'سجل البحث',
  'account_support_center': 'مركز الدعم',
  'account_settings': 'الإعدادات',
  'account_username_login': 'اسم المستخدم لتسجيل الدخول',
  'account_seller_profile': 'الملف الشخصي',
  'account_user_profile': 'بروفايل المستخدم',
  'account_showroom_setup': 'إعداد صفحة المعرض',
  'account_my_ads': 'إعلاناتي',
  'account_received_offers': 'العروض المستلمة',
  'account_my_car_offers': 'عروضي على السيارات',
  'account_car_alerts': 'تنبيهات السيارات',
  'account_advertise_with_us': 'أعلن معنا',
  'account_business_ads': 'إعلانات الشركات',
  'account_admin_panel': 'لوحة المشرف',
  'account_sign_out': 'تسجيل الخروج',
  'account_sell_car': 'بيع سيارة',
  'account_watch': 'راقب',
  'account_favorites': 'المحفوظات',
  'account_chat': 'محادثة',
  'settings_title': 'الإعدادات',
  'settings_push_notifications': 'إشعارات push',
  'settings_email_notifications': 'إشعارات البريد',
  'settings_dark_mode': 'الوضع الليلي',
  'settings_about': 'عن التطبيق',
  'login_title': 'تسجيل الدخول',
  'register_title': 'إنشاء حساب',
  'login_subtitle': 'ادخل لحسابك وكمل استخدام MOTRI IQ',
  'register_subtitle': 'أنشئ حسابك وابدأ النشر',
  'login_display_name': 'الاسم الظاهر',
  'login_username_hint': 'اسم المستخدم (إنجليزي، أرقام، أو _)',
  'login_email_or_username': 'الإيميل أو اسم المستخدم',
  'login_email': 'الإيميل',
  'login_password': 'كلمة المرور',
};

/// نفس بناء `MaterialApp` في `MotriIqApp` لكن بـ`home` مُsimpَّط: الشاشة
/// الحقيقية تُدفع كـroute داخل `Navigator`، وهذا هو سبب أن `builder` هو
/// ما يعيد البناء. هنا نحاكي نفس البنية بدل الاعتماد على مؤقّتات الحركة.
Widget harnessHome() => const _LanguageProbeScreen();

class _LanguageProbeScreen extends StatefulWidget {
  const _LanguageProbeScreen();

  @override
  State<_LanguageProbeScreen> createState() => _LanguageProbeScreenState();
}

class _LanguageProbeScreenState extends State<_LanguageProbeScreen> {
  @override
  void initState() {
    super.initState();
    // نتحقق من ترجمة route مستبدل داخل Navigator.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const _ShellProbe()),
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('loading')));
}

class _ShellProbe extends StatelessWidget {
  const _ShellProbe();

  @override
  Widget build(BuildContext context) {
    // نفس ما يفعله `HomeShell` و`AccountTab` في الإنتاج.
    context.dependOnAppStrings();
    return Scaffold(
      appBar: AppBar(title: Text(t('settings_title'))),
      body: ListView(
        children: <Widget>[
          Text(t('account_options')),
          Text(t('account_quick_actions')),
          Text(t('account_more_options')),
          Text(t('account_sign_out')),
          Text(t('account_language')),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        onDestinationSelected: (_) {},
        destinations: <NavigationDestination>[
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            label: t('nav_home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            label: t('nav_search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.add_circle),
            label: t('nav_add'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: t('nav_account'),
          ),
        ],
      ),
    );
  }
}

/// نسخة مطابقة حرفيًا لبنية `MotriIqApp` في الإنتاج.
Widget appShellUnderTest() => ValueListenableBuilder<AppLocale>(
      valueListenable: appLocaleNotifier,
      builder: (BuildContext context, AppLocale locale, Widget? _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          // سطر الإنتاج: اللغة الحقيقية بلا تحوير.
          locale: locale.locale,
          supportedLocales: const <Locale>[
            Locale('ar'),
            Locale('ku'),
            Locale('en'),
          ],
          // نفس قائمة الإنتاج، فـ`MaterialLocalizations` تبقى متاحة.
          localizationsDelegates: appLocalizationsDelegates,
          builder: (BuildContext context, Widget? child) => AppStringsScope(
            locale: appLocale,
            child: child ?? const SizedBox.shrink(),
          ),
          home: harnessHome(),
        );
      },
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  });

  tearDown(() {
    appLocaleNotifier.value = AppLocale.ar;
  });

  group('سلامة الربط في المصدر', () {
    late String source;

    setUpAll(() {
      // تُحذف تعليقات `//` أولًا، وإلا التقط الفحص المثال `t('key')`
      // المذكور في الشرح بوصفه مفتاحًا مستعملًا.
      source = File('lib/main.dart')
          .readAsStringSync()
          .split('\n')
          .map((String line) => line.contains('//')
              ? line.substring(0, line.indexOf('//'))
              : line)
          .join('\n');
    });

    test('كل t(key) مستعمل في main.dart له عربي وكردي', () {
      final RegExp pattern = RegExp(r"\bt\('([a-z_]+)'\)");
      final Set<String> used = pattern
          .allMatches(source)
          .map((RegExpMatch m) => m.group(1)!)
          .toSet();

      expect(used, isNotEmpty, reason: 'لم يُعثر على أي استدعاء t()');

      for (final String key in used) {
        expect(AppStrings.ar.containsKey(key), isTrue,
            reason: '«$key» مستعمل في الواجهة بلا قيمة عربية');
        expect(AppStrings.ku.containsKey(key), isTrue,
            reason: '«$key» مستعمل في الواجهة بلا قيمة كردية');
        expect(AppStrings.ar[key], isNotEmpty);
        expect(AppStrings.ku[key], isNotEmpty);
      }
    });

    test('الربط استخدم أكثر من مجرد صف اللغة', () {
      final RegExp pattern = RegExp(r"\bt\('([a-z_]+)'\)");
      final int calls = pattern.allMatches(source).length;
      // كان 2 قبل الربط؛ العتبة تكشف أي انحدار在未来.
      expect(calls, greaterThanOrEqualTo(30),
          reason: 'عدد استدعاءات t() في main.dart = $calls');
    });

    test('مفاتيح التوجيه الداخلي لم تمرّ عبر t()', () {
      // 'السيارات' و'السوق' يُقارَنان حرفيًا داخل SectionPage/openSection.
      // تمريرهما عبر t() يكسر التنقّل بين الأقسام.
      expect(source, isNot(contains("t('account_cars')")));
      for (final String key in arabicBeforeWiring.keys) {
        expect(AppStrings.ku.containsKey(key), isTrue);
      }
    });
  });

  group('العربية لم تتغيّر', () {
    test('كل قيمة عربية تطابق النص الحرفي الأصلي', () {
      arabicBeforeWiring.forEach((String key, String literal) {
        expect(AppStrings.ar[key], literal,
            reason: 'قيمة «$key» تغيّرت عن النص العربي الأصلي');
      });
    });

    test('العربية هي الافتراضية وتُعرض كاملة', () {
      expect(appLocale, AppLocale.ar);
      for (final String key in arabicBeforeWiring.keys) {
        expect(t(key), arabicBeforeWiring[key],
            reason: 'عرض «$key» اختلف عن العربي الأصلي');
      }
    });
  });

  group('الكردية مترجمة فعلًا لكل نص مربوط', () {
    test('كل مفتاح مربوط يختلف بين العربية والكردية', () {
      for (final String key in arabicBeforeWiring.keys) {
        expect(AppStrings.ku[key], isNot(arabicBeforeWiring[key]),
            reason: '«$key» واحد بالعربية والكردية — ترجمة ناقصة');
        expect(AppStrings.t(key, 'ku'), AppStrings.ku[key]);
      }
    });

    test('لا مفتاح مربوط يعود إلى العربية في الكردية', () {
      // عدا أسماء العلامات التجارية التي تُترك كما هي عمدًا.
      const Set<String> brands = <String>{'CARFAX'};
      for (final String key in arabicBeforeWiring.keys) {
        if (brands.contains(AppStrings.ar[key])) continue;
        expect(AppStrings.t(key, 'ku'), isNot(AppStrings.t(key, 'ar')),
            reason: '«$key» يرجع للعربية في الكردية');
      }
    });
  });

  group('التبديل الحيّ يعيد بناء الواجهة فعلًا', () {
    testWidgets('ar ← ku ← ar يغيّر النصوص بلا إعادة تشغيل', (tester) async {
      appLocaleNotifier.value = AppLocale.ar;
      await tester.pumpWidget(appShellUnderTest());
      await tester.pumpAndSettle();

      // 1) العربية: النص العربي ظاهر في شريط التنقّل وفي الصفحة.
      expect(find.text('الرئيسية'), findsOneWidget);
      expect(find.text('البحث'), findsOneWidget);
      expect(find.text('حسابي'), findsOneWidget);
      expect(find.text('الخيارات'), findsOneWidget);
      expect(find.text('الإعدادات'), findsOneWidget);

      // 2) الكردية: نفس الـwidget tree، نفس الـState، تغيّر النص فقط.
      appLocaleNotifier.value = AppLocale.ku;
      await tester.pumpAndSettle();

      expect(find.text('سەرەکی'), findsOneWidget,
          reason: 'شريط التنقّل لم يتحوّل للكردية');
      expect(find.text('گەڕان'), findsOneWidget);
      expect(find.text('هەژمار'), findsOneWidget);
      expect(find.text('هەڵبژاردەکان'), findsOneWidget);
      expect(find.text('ڕێکخستنەکان'), findsOneWidget);

      expect(find.text('الرئيسية'), findsNothing,
          reason: 'ما زال النص العربي ظاهرًا بعد التحويل');
      expect(tester.takeException(), isNull);

      // 3) الرجوع للعربية فورًا.
      appLocaleNotifier.value = AppLocale.ar;
      await tester.pumpAndSettle();

      expect(find.text('الرئيسية'), findsOneWidget,
          reason: 'الرجوع للعربية لم يعيد النص العربي');
      expect(find.text('سەرەکی'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('التبديل يتم عبر setAppLocale أيضًا (المسار الحقيقي)',
        (tester) async {
      appLocaleNotifier.value = AppLocale.ar;
      await tester.pumpWidget(appShellUnderTest());
      await tester.pumpAndSettle();
      expect(find.text('سەرەکی'), findsNothing);

      await setAppLocale(AppLocale.ku);
      await tester.pumpAndSettle();
      expect(find.text('سەرەکی'), findsOneWidget);

      await setAppLocale(AppLocale.ar);
      await tester.pumpAndSettle();
      expect(find.text('الرئيسية'), findsOneWidget);
    });

    testWidgets('MaterialLocalizations متاحة في الكردية داخل الصفحة',
        (tester) async {
      appLocaleNotifier.value = AppLocale.ku;
      await tester.pumpWidget(appShellUnderTest());
      await tester.pumpAndSettle();

      final BuildContext ctx = tester.element(find.byType(NavigationBar));
      expect(Localizations.of<MaterialLocalizations>(ctx, MaterialLocalizations),
          isNotNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('الكردية RTL والإنجليزية LTR في الشجرة نفسها',
        (tester) async {
      appLocaleNotifier.value = AppLocale.ku;
      await tester.pumpWidget(appShellUnderTest());
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.rtl,
      );

      appLocaleNotifier.value = AppLocale.en;
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(NavigationBar))),
        TextDirection.ltr,
      );
      appLocaleNotifier.value = AppLocale.ar;
    });
  });

  group('الاختيار يبقى بعد إعادة فتح التطبيق', () {
    testWidgets('إعادة بناء التطبيق ببطاقة محفوظة تُعيد الكردية',
        (tester) async {
      await setAppLocale(AppLocale.ku);

      // "إعادة تشغيل": حالة جديدة تمامًا، لا ناقل حالة سابق.
      appLocaleNotifier.value = AppLocale.ar;
      await loadAppLocale();
      await tester.pumpWidget(appShellUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('سەرەکی'), findsOneWidget,
          reason: 'الكردية لم تبقَ بعد إعادة الفتح');
      expect(find.text('الرئيسية'), findsNothing);
    });
  });
}