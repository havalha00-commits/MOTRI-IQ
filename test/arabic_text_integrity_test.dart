// اختبار سلامة الترميز في النصوص العربية المرسومة.
//
// لماذا هذا الاختبار
// -----------------
//
// تلفّت مرة نصوص `lib/main.dart` كلّها: حُفظ الملف بعد قراءته بترميز cp1256
// بدل UTF-8، فصار «المفضلة» تُقرأ `ط§ظ„ظ…ظپط¶ظ„ط©`. النتيجة أن الصفحات
// التي نصوصها من جدول الترجمة (`t()`) بقيت سليمة، بينما الصفحات التي فيها
// نصوص مكتوبة مباشرة — ومنها «حسابي» — ظهرت عربيةً مكسورة.
//
// الفحص هنا لا يبحث عن كلمات بعينها. `§` و`Ù` و`Ø` و`â` و`ï¿½` لا وجود لها
// في نص عربي سليم إطلاقًا، و`ï¿½` هو بالذات ما كان يخفيه التلف قبل إصلاحه.
// ظهور أيٍّ منها يعني أن الملف قُرئ بترميز غير ترميزه.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';

/// محارف لا وجود لها في نص عربي سليم، ووجودها دليل تلف ترميز.
const String kMojibakeChars = 'ÙØâÃÑƒï¿½§¤¢£¥¬°';

/// كل نصّ يرسمه الشجرة الحالية.
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
  return found.toList();
}

/// يفشل باسم [where] إن حوى أي نصّ علامة تلف.
void expectNoMojibake(List<String> texts, String where) {
  final RegExp broken =
      RegExp('[${RegExp.escape(kMojibakeChars)}\uFFFD]');
  for (final String text in texts) {
    expect(broken.hasMatch(text), isFalse,
        reason: 'نصّ تالف الترميز في $where: "$text"');
  }
}

/// نفس بناء `MaterialApp` في الإنتاج مع فرض العربية.
Widget arHost(Widget child) => ValueListenableBuilder<AppLocale>(
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
          home: child,
        );
      },
    );

/// الصفحات التي يفحصها هذا الاختبار: شاشة «حسابي» أولًا، ثم بقية التطبيق
/// حتى لا يصلح خللٌ في مكان على حساب تلفٍ في غيره.
List<({String name, Widget page})> screens() => <({String name, Widget page})>[
      (name: 'AccountTab', page: const Scaffold(body: AccountTab())),
      (name: 'SettingsPage', page: const Scaffold(body: SettingsPage())),
      (name: 'AboutPage', page: const Scaffold(body: AboutPage())),
      (name: 'HomeTab', page: const Scaffold(body: HomeTab())),
      (name: 'SearchTab', page: const Scaffold(body: SearchTab())),
      (name: 'FavoritesPage', page: const Scaffold(body: FavoritesPage())),
      (name: 'UserProfilePage', page: const Scaffold(body: UserProfilePage())),
      (name: 'SellerProfilePage',
          page: const Scaffold(
              body: SellerProfilePage(sellerId: 'x', sellerName: 'بائع'))),
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

  for (final ({String name, Widget page}) screen in screens()) {
    testWidgets('${screen.name} — لا نصّ تالف بالعربية', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      appLocaleNotifier.value = AppLocale.ar;
      await tester.pumpWidget(arHost(screen.page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // `UserProfilePage` يرمي تأكيد Material 3 المعروف
      // «ListTile background color or ink splashes may be invisible»، وهو
      // موضوعه تلوين الصفّ لا الترميز، وموثّق في `ui_probe_test.dart`. نبلعه
      // هنا عمدًا حتى لا يحجب فحص العربية هذا الملف.
      tester.takeException();

      final List<String> texts = renderedText(tester);
      expect(texts, isNotEmpty, reason: '${screen.name} لم ترسم أي نصّ');
      expectNoMojibake(texts, screen.name);
    });
  }

  testWidgets('«حسابي» يُعرض RTL بلا فييض', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    appLocaleNotifier.value = AppLocale.ar;
    await tester.pumpWidget(arHost(const Scaffold(body: AccountTab())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AccountTab), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'استثناء أو فييض أثناء عرض «حسابي» بالعربية');
  });
}
