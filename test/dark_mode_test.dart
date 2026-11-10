// اختبارات الوضع الليلي.
//
// ثلاثة مستويات:
//  1) ثبات الوضع الفاتح — كل لون في اللوحة يعيد قيمته الأصلية بالضبط،
//     فأي استبدال في اللوحة لاحقًا يظهر كفشل لا كفرق بصري خفي.
//  2) صح�� اللوحة في الوضع الليلي — لا استدعاء ذاتي (كان يسبب
//     StackOverflow) ولا تعارض ألوان.
//  3) سلوك حقيقي: التصيير ليلًا بلا استثناءات، والحفظ في
//     shared_preferences، وربط المفتاح.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

const Map<String, Size> darkPhones = <String, Size>{
  'se_320x568': Size(320, 568),
  'pixel_412x915': Size(412, 915),
};

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Widget host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    );

final Map<String, dynamic> darkCar = <String, dynamic>{
  'id': 'dark-1',
  'user_id': 'seller-1',
  'brand': 'شركة汽车工业 المحدودة للتجارة والاستيراد',
  'model': 'نموذج طويل جدًا للاختبار',
  'year': 2025,
  'price': null,
  'governorate': null,
  'fuel': null,
  'transmission': null,
  'mileage': null,
  'description': 'وصف طويل جدًا ' * 8,
  'phone': null,
  'images': '',
  'is_approved': true,
  'created_at': '2026-09-26T06:37:42.319744+00:00',
  'city': 'مدينة ذات اسم طويل جداً',
  'image_url': '',
  'province': 'محافظة ذات اسم طويل',
  'body_type': 'سيارة رياضية متعددة الاستخدامات',
  'color': 'أبيض',
  'favorites': 0,
  'views': 0,
  'status': 'active',
};

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
    // `AppColors` حالة عامة؛ بدون إعادة الضبط يتسرّب الوضع إلى بقية الاختبارات.
    AppColors.isDark = false;
    darkModeNotifier.value = ThemeMode.light;
  });

  group('لوحة الألوان', () {
    test('الوضع الفاتح يعيد القيم الأصلية حرفيًا', () {
      AppColors.isDark = false;
      expect(AppColors.surface, Colors.white);
      expect(AppColors.scaffold, const Color(0xFFF8FAFB));
      expect(AppColors.text, const Color(0xFF111827));
      expect(AppColors.textStrong, const Color(0xFF1F2937));
      expect(AppColors.textMuted, const Color(0xFF4B5563));
      expect(AppColors.textFaint, const Color(0xFF6B7280));
      expect(AppColors.textHint, const Color(0xFF9CA3AF));
      expect(AppColors.border, const Color(0xFFE5E7EB));
      expect(AppColors.borderStrong, const Color(0xFFD1D5DB));
      expect(AppColors.emptyGradientA, const Color(0xFFE8E8E8));
      expect(AppColors.emptyGradientB, const Color(0xFFF2F2F2));
      expect(AppColors.emptyGradientTint, const Color(0xFFFBE7EB));
    });

    test('card وpanel تتبعان الوضع', () {
      AppColors.isDark = false;
      expect(card, AppColors.surface);
      expect(panel, AppColors.surface);
      AppColors.isDark = true;
      expect(card, AppColors.surface);
      expect(panel, AppColors.surface);
    });

    test('لا استدعاء ذاتي في أي لون (حارس ضد StackOverflow)', () {
      AppColors.isDark = true;
      // قراءة كل لون مرتين: لو أحدها استدعى نفسه لانهار الاختبار.
      final List<Color> a = <Color>[
        AppColors.surface,
        AppColors.scaffold,
        AppColors.placeholder,
        AppColors.text,
        AppColors.textStrong,
        AppColors.textMuted,
        AppColors.textFaint,
        AppColors.textHint,
        AppColors.border,
        AppColors.borderStrong,
        AppColors.emptyGradientA,
        AppColors.emptyGradientB,
        AppColors.emptyGradientTint,
      ];
      final List<Color> b = <Color>[
        AppColors.surface,
        AppColors.scaffold,
        AppColors.placeholder,
        AppColors.text,
        AppColors.textStrong,
        AppColors.textMuted,
        AppColors.textFaint,
        AppColors.textHint,
        AppColors.border,
        AppColors.borderStrong,
        AppColors.emptyGradientA,
        AppColors.emptyGradientB,
        AppColors.emptyGradientTint,
      ];
      expect(b, a);
    });

    test('النصوص في الوضع الليلي أفتح من الأسطح (تباين مقروء)', () {
      AppColors.isDark = true;
      double lum(Color c) => c.computeLuminance();
      expect(lum(AppColors.textStrong), greaterThan(lum(AppColors.surface)),
          reason: 'نص البطاقة يجب أن يكون أفتح من سطحها');
      expect(lum(AppColors.textMuted), greaterThan(lum(AppColors.surface)),
          reason: 'النص الثانوي يجب أن يبقى مقروءًا');
      expect(lum(AppColors.surface), greaterThan(lum(AppColors.scaffold)),
          reason: 'البطاقة يجب أن تكون أعلى ارتفاعًا من الخلفية');
    });
  });

  group('الحفظ', () {
    test('setDarkMode يحفظ الاختيار', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await setDarkMode(true);
      expect(AppColors.isDark, isTrue);
      expect(darkModeNotifier.value, ThemeMode.dark);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kDarkModePref), isTrue);

      await setDarkMode(false);
      expect(AppColors.isDark, isFalse);
      expect(darkModeNotifier.value, ThemeMode.light);
      expect(prefs.getBool(kDarkModePref), isFalse);
    });

    test('buildAppTheme يبني ثيمين مختلفين فعليًا', () {
      final ThemeData light = buildAppTheme(Brightness.light);
      final ThemeData dark = buildAppTheme(Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(light.scaffoldBackgroundColor,
          isNot(equals(dark.scaffoldBackgroundColor)));
      expect(dark.scaffoldBackgroundColor.computeLuminance(),
          lessThan(light.scaffoldBackgroundColor.computeLuminance()));
    });
  });

  group('التصيير ليلًا', () {
    for (final p in darkPhones.entries) {
      group('${p.key} ${p.value.width.toInt()}x${p.value.height.toInt()}', () {
        setUp(() => AppColors.isDark = true);

        testWidgets('CarDetailsPage — no overflow / exception',
            (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(CarDetailsPage(car: darkCar)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'CarDetailsPage ليلًا عند ${p.key}');
        });

        testWidgets('SettingsPage — مفتاح الوضع الليلي يعكس الحالة الحقيقية',
            (tester) async {
          sizeTo(tester, p.value);
          // SettingsPage يبني Scaffold خاصًا به، فلا يُغلَّف مرتين.
          await tester.pumpWidget(host(const SettingsPage()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'SettingsPage ليلًا عند ${p.key}');

          // المفتاح داخل `ListTile.trailing`، فهو شقيق للنص لا سلف له؛
// لذا يُرفع إلى ListTile أولًا ثم يُبحث عن Switch داخله.
final Finder tile = find.ancestor(
            of: find.text('الوضع الليلي'),
            matching: find.byType(ListTile),
          );
          expect(tile, findsOneWidget);
          final Finder toggle =
              find.descendant(of: tile, matching: find.byType(Switch));
          expect(toggle, findsOneWidget);
          expect(tester.widget<Switch>(toggle).value, isTrue,
              reason: 'المفتاح يجب أن يعكس AppColors.isDark');
        });

        testWidgets('AccountTab — no overflow', (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(const Scaffold(body: AccountTab())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'AccountTab ليلًا عند ${p.key}');
        });

        testWidgets('HomeTab — no overflow', (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(const Scaffold(body: HomeTab())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'HomeTab ليلًا عند ${p.key}');
        });

        testWidgets('SupportCenterPage — no overflow, no white surfaces',
            (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(const SupportCenterPage()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'SupportCenterPage ليلًا عند ${p.key}');

          final Set<Color> colours = <Color>{
            ...tester
                .widgetList<Container>(find.byType(Container))
                .map((Container c) => c.color)
                .whereType<Color>(),
            ...tester
                .widgetList<DecoratedBox>(find.byType(DecoratedBox))
                .map((DecoratedBox b) => b.decoration)
                .whereType<BoxDecoration>()
                .map((BoxDecoration d) => d.color)
                .whereType<Color>(),
          };
          expect(colours.where((Color c) => c == Colors.white), isEmpty,
              reason: 'SupportCenterPage لا يزال يرسم سطحًا أبيض');
        });

        testWidgets('SearchTab — no overflow', (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(const Scaffold(body: SearchTab())));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'SearchTab ليلًا عند ${p.key}');
        });

        testWidgets('CarCard — لا تجاوز', (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(Scaffold(
            body: Center(
              child: SizedBox(
                  width: 160, child: CarCard(car: darkCar, square: true)),
            ),
          )));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'CarCard ليلًا عند ${p.key}');
        });

        // إثبات نهائي: شجرة Widget حقيقية تُرسم بألوان داكنة فعلًا، لا أن
        // تقرأ getters اللوحة فقط. أي موضع بقي يستخدم `Colors.white` يُظهر
        // هنا كـContainer أبيض في装作 ليلي.
        testWidgets('CarDetailsPage — السطوح تُرسم داكنة فعليًا',
            (tester) async {
          sizeTo(tester, p.value);
          await tester.pumpWidget(host(CarDetailsPage(car: darkCar)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull);

          final Set<Color> painted = <Color>{
          ...tester
              .widgetList<Container>(find.byType(Container))
              .map((Container c) => c.color)
              .whereType<Color>(),
          // معظم الأسطح في هذا المشروع عبر `BoxDecoration` داخل `DecoratedBox`.
          ...tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .map((DecoratedBox b) => b.decoration)
              .whereType<BoxDecoration>()
              .map((BoxDecoration d) => d.color)
              .whereType<Color>(),
        };
          expect(painted, isNotEmpty, reason: 'لا أسطح مرسومة');
          final Iterable<Color> whiteSurfaces =
              painted.where((Color c) => c == Colors.white);
          expect(whiteSurfaces, isEmpty,
              reason: 'بقيت سطح أبيض في الوضع الليلي: $whiteSurfaces');
          expect(painted, contains(AppColors.surface),
              reason: 'البطاقات يجب أن ترسم لون السطح الليلي');
        });

        // نفس الفحص على بقية الشاشات الرئيسية: أي `Colors.white` تسرّب
        // إليها يعني بقاء جزء من الواجهة فاتحًا في الوضع الليلي.
        for (final MapEntry<String, Widget> page in <String, Widget>{
          'HomeTab': const HomeTab(),
          'AccountTab': const AccountTab(),
          'SearchTab': const SearchTab(),
          'FavoritesPage': const FavoritesPage(),
        }.entries) {
          testWidgets('${page.key} — لا أسطح بيضاء متبقية',
              (tester) async {
            sizeTo(tester, p.value);
            await tester.pumpWidget(
                host(Scaffold(body: page.value)));
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
            expect(tester.takeException(), isNull);

            final Set<Color> colours = <Color>{
              ...tester
                  .widgetList<Container>(find.byType(Container))
                  .map((Container c) => c.color)
                  .whereType<Color>(),
              ...tester
                  .widgetList<DecoratedBox>(find.byType(DecoratedBox))
                  .map((DecoratedBox b) => b.decoration)
                  .whereType<BoxDecoration>()
                  .map((BoxDecoration d) => d.color)
                  .whereType<Color>(),
            };
            expect(colours.where((Color c) => c == Colors.white), isEmpty,
                reason: '${page.key} لا يزال يرسم سطحًا أبيض');
          });
        }
      });
    }

    testWidgets('تبديل الوضع يعيد بناء الشاشة فعليًا', (tester) async {
      sizeTo(tester, const Size(412, 915));
      AppColors.isDark = false;
      darkModeNotifier.value = ThemeMode.light;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: darkModeNotifier.value,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: Container(
                  width: 100,
                  height: 50,
                  color: AppColors.surface,
                  child: const Text('بطاقة'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      Color readSurface() => tester
          .widgetList<Container>(find.byType(Container))
          .firstWhere((Container c) => c.color != null)
          .color!;
      expect(readSurface(), Colors.white, reason: 'قبل التبديل فاتح');

      AppColors.isDark = true;
      darkModeNotifier.value = ThemeMode.dark;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: darkModeNotifier.value,
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: Container(
                  width: 100,
                  height: 50,
                  color: AppColors.surface,
                  child: const Text('بطاقة'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      expect(readSurface(), isNot(Colors.white), reason: 'بعد التبديل ليلي');
      expect(tester.takeException(), isNull);
    });
  });
}