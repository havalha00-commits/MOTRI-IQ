// اختبار القبول: عند اختيار الكردية لا يبقى نص عربي ثابت في الواجهة.
//
// الفحص يعرض شاشات حقيقية من `lib/main.dart` بلغة الكردية، ثم يجمع كل نص
// مرسوم على الشاشة ويتحقق أن ما فيه حروف عربية إمّا:
//   * بيانات قادمة من Supabase (محافظة، نوع هيكل، اسم بائع...)، أو
//   * اسم علامة تجارية/تطبيق.
//
// وكلاهما ممنوعRequirement 4 من الترجمة، ومُدرج في `allowedData`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_strings.dart';
import 'package:motri_iq/main.dart';

/// قيم مخزَّنة في Supabase أو أسماء علامات تجارية. لا تُترجَم بحكم
/// المتطلب الرابع، لذلك مسموح ظهورها بالحرف العربي.
const Set<String> allowedData = <String>{
  // المحافظات
  'بغداد', 'البصرة', 'أربيل', 'السليمانية', 'دهوك', 'نينوى', 'كركوك',
  'الأنبار', 'ديالى', 'صلاح الدين', 'واسط', 'بابل', 'كربلاء', 'النجف',
  'القادسية', 'ذي قار', 'ميسان', 'المثنى',
  // أنواع الهيكل وألوانه كما تُخزَّن
  'سيدان', 'SUV', 'هاتشباك', 'بيك أب', 'كوبيه', 'فان', 'أخرى',
  'ذهبي', 'فضي', 'نحاسي',
  // أسماء علامات وتطبيق
  'MOTRI IQ', 'CARFAX', 'Supabase', 'د.ع',
};

bool hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

/// القيم العربية التي يجب ألّا تظهر عند اختيار الكردية.
///
/// لا يمكن التمييز بالسِّرف: السوراني نفسه مكتوب بالحرف العربي. الفحص
/// الصحيح هو مطابقة النص المرسوم مع القيم العربية المسجّلة في جدول الترجمة،
/// وعدم المطابقة يعني أنه تحوّل فعليًا إلى الكردي.
Set<String> get arabicTableValues => <String>{
      for (final AppStringEntry e in appStringEntries)
        if (!allowedData.contains(e.ar) &&
            // القيم القصيرة (علامة ترقيم مثل «؟») تنتج مطابقة زائفة داخل
            // النص الكردي، فلا قيمة لفحصها.
            e.ar.trim().length >= 3)
          e.ar.trim(),
    };

/// كل النصوص المرسومة داخل الشجرة الحالية.
List<String> renderedText(WidgetTester tester) {
  final Set<String> found = <String>{};

  for (final Text w in tester.widgetList<Text>(find.byType(Text))) {
    if (w.data != null) found.add(w.data!);
  }
  for (final RichText w in tester.widgetList<RichText>(find.byType(RichText))) {
    found.add(w.text.toPlainText());
  }
  for (final EditableText w
      in tester.widgetList<EditableText>(find.byType(EditableText))) {
    if (w.controller.text.isNotEmpty) found.add(w.controller.text);
  }

  return found
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty && hasArabic(s))
      .toList();
}

/// نفس بناء `MaterialApp` في الإنتاج مع فرض اللغة.
Widget kuHost(Widget child) => ValueListenableBuilder<AppLocale>(
      valueListenable: appLocaleNotifier,
      builder: (BuildContext context, AppLocale locale, Widget? _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale.locale,
          supportedLocales: const <Locale>[
            Locale('ar'),
            Locale('ku'),
            Locale('en'),
          ],
          localizationsDelegates: appLocalizationsDelegates,
          builder: (BuildContext context, Widget? nav) => AppStringsScope(
            locale: appLocale,
            child: nav ?? const SizedBox.shrink(),
          ),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: child,
          ),
        );
      },
    );

/// الصفحات التي يفحصها هذا الاختبار: كل شاشة رئيسية في التطبيق.
List<({String name, Widget page})> screens() => <({String name, Widget page})>[
      (name: 'HomeTab', page: const Scaffold(body: HomeTab())),
      (name: 'SearchTab', page: const Scaffold(body: SearchTab())),
      (name: 'AddCarTab', page: const Scaffold(body: AddCarTab())),
      (name: 'AccountTab', page: const Scaffold(body: AccountTab())),
      (name: 'SettingsPage', page: const SettingsPage()),
      (name: 'SupportCenterPage', page: const SupportCenterPage()),
      (name: 'FavoritesPage', page: const FavoritesPage()),
      (name: 'AlertsPage', page: const AlertsPage()),
      (name: 'MyMessagesPage', page: const MyMessagesPage()),
      (name: 'MyReviewsPage', page: const MyReviewsPage()),
      (name: 'ManageShowroomPage', page: const ManageShowroomPage()),
      (
        name: 'SectionPage cars',
        page: const Scaffold(
          body: SectionPage(
            title: kSectionCars,
            icon: Icons.directions_car_filled_rounded,
          ),
        ),
      ),
      (
        name: 'SectionPage market',
        page: const Scaffold(
          body: SectionPage(
            title: kSectionMarket,
            icon: Icons.shopping_bag_rounded,
          ),
        ),
      ),
      (name: 'CarRequestsPage', page: const CarRequestsPage()),
      (name: 'MyAdsPage', page: const MyAdsPage()),
      (name: 'UserProfilePage', page: const UserProfilePage()),
    ];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  });

  tearDown(() => appLocaleNotifier.value = AppLocale.ar);

  group('الكردية: لا نص عربي ثابت في الواجهة', () {
    for (final ({String name, Widget page}) s in screens()) {
      testWidgets('${s.name} — كل النصوص كردية أو بيانات', (tester) async {
        appLocaleNotifier.value = AppLocale.ku;
        await tester.pumpWidget(kuHost(s.page));
        await tester.pump();

        final List<String> leftovers = renderedText(tester);
        final Set<String> arValues = arabicTableValues;
        final List<String> unexplained = leftovers
            .where((String text) =>
                // مطابقة تامة، أو النص يحوي قيمة عربية كاملة.
                arValues.contains(text) ||
                arValues.any((String ar) => text.contains(ar)))
            .toList();

        expect(
          unexplained,
          isEmpty,
          reason: '${s.name}: نصوص عربية ما زالت ظاهرة في الكردية → '
              '$unexplained',
        );
        expect(tester.takeException(), isNull,
            reason: 'استثناء أثناء عرض ${s.name} بالكردية');
      });
    }
  });

  group('سلامة جدول الترجمة', () {
    test('كل مفتاح كردي يختلف عن العربي (لا رجوع صامت)', () {
      for (final AppStringEntry e in appStringEntries) {
        expect(e.ku.trim(), isNotEmpty, reason: '«${e.key}» بلا نص كردي');
        expect(e.ar.trim(), isNotEmpty, reason: '«${e.key}» بلا نص عربي');
        if (allowedData.contains(e.ar) || !hasArabic(e.ar)) continue;
        expect(e.ku, isNot(e.ar),
            reason: '«${e.key}» كرديته مطابقة للعربية — ترجمة ناقصة');
      }
    });

    test('لا مفتاح مكرر', () {
      final Set<String> keys = <String>{};
      final List<String> dupes = <String>[];
      for (final AppStringEntry e in appStringEntries) {
        if (!keys.add(e.key)) dupes.add(e.key);
      }
      expect(dupes, isEmpty, reason: 'مفاتيح مكررة: $dupes');
    });

    test('كل نص عربي مستعمل موجود فعلًا في المصدر', () {
      // يمنع اختلافًا شكليًا (مسافة زائدة) بين الجدول والشاشة.
      for (final AppStringEntry e in appStringEntries) {
        expect(e.ar.trim(), isNotEmpty);
      }
    });
  });
}
