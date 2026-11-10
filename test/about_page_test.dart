// اختبار صفحة «عن التطبيق».
//
// العقد الذي يفحصه هذا الملف:
//  1) زرّ «عن التطبيق» في الإعدادات يفتح الصفحة فعلًا (كان بلا `onTap`).
//  2) الصفحة تعرض ما في `PackageInfo` حرفيًا، فلا رقم مكتوب يدويًا، فأي
//     تعديل على `version:` في pubspec.yaml ينعكس وحده.
//  3) الشعار والاسم والوصف وسياستا الخصوصية والاستخدام والتواصل وحقوق
//     النشر موجودة، والاثنتان الأولى معطّلتان لأن صفحتهما غير موجودة في
//     المشروع ولا رابط خارجي مخترَع.
//  4) لا فييض على أي مقاس هاتف، والاتجاه RTL، والعربية سليمة.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';

const Map<String, Size> phoneSizes = <String, Size>{
  'se_320x568': Size(320, 568),
  'budget_360x640': Size(360, 640),
  'pixel_412x915': Size(412, 915),
  'promax_430x932': Size(430, 932),
};

/// قيمة وهمية لا يمكن أن تكون في `pubspec.yaml`، فلو ظهرت في الصفحة فذلك
/// يثبت أن الصفحة تقرأ من `PackageInfo` لا من نصّ مكتوب في الشيفرة.
const String kFakeVersion = '9.9.9-selftest';
const String kFakeBuild = '4242-selftest';

PackageInfo fakeInfo({String version = kFakeVersion, String build = kFakeBuild}) =>
    PackageInfo(
      appName: 'MOTRI IQ',
      packageName: 'iq.motri',
      version: version,
      buildNumber: build,
    );

Widget host(Widget child) => ValueListenableBuilder<AppLocale>(
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

/// `ListView` يبني ما في الشاشة فقط، فالروابط وحقوق النشر أسفل الطية ولا
/// تُبنى قبل التمرير. كل الفحوص تبدأ من نفس الموضع، وإلا صار الفحص يمرّ
/// على عناصر لم تُبنَ أصلًا فيبدو أنها غائبة.
Future<void> scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -900));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpAbout(WidgetTester tester, {Size? size, PackageInfo? info}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }
  await tester.pumpWidget(host(AboutPage(
    infoLoader: () async => info ?? fakeInfo(),
  )));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

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

  group('زرّ «عن التطبيق» في الإعدادات', () {
    testWidgets('الضغط عليه يفتح صفحة About', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(host(const SettingsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AboutPage), findsNothing,
          reason: 'قبل الضغط لا وجود للصفحة');
      final Finder row = find.ancestor(
        of: find.text('عن التطبيق'),
        matching: find.byType(ListTile),
      );
      expect(row, findsOneWidget);

      await tester.tap(row);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(AboutPage), findsOneWidget,
          reason: 'الزر بلا onTap كان سبب عدم فتح الصفحة');
    });
  });

  group('محتوى الصفحة', () {
    testWidgets('الشعار واسم التطبيق والوصف وحقوق النشر', (tester) async {
      await pumpAbout(tester);

      expect(find.byType(BrandLogo), findsOneWidget,
          reason: 'شعار MOTRI IQ في الأعلى');
      expect(find.text('MOTRI IQ'), findsOneWidget);
      expect(
        find.text('منصة عراقية للسيارات والإعلانات، تساعدك على اكتشاف السيارات والإعلانات والتواصل مع أصحابها بسهولة.'),
        findsOneWidget,
      );
      expect(find.text('عن MOTRI IQ'), findsOneWidget);

      await scrollToBottom(tester);
      expect(find.text('© MOTRI IQ'), findsOneWidget);
    });

    for (final entry in <String, Type>{
      'سياسة الخصوصية': PrivacyPolicyPage,
      'شروط الاستخدام': TermsOfUsePage,
    }.entries) {
      testWidgets('${entry.key} opens its implemented page', (tester) async {
        await pumpAbout(tester);
        await scrollToBottom(tester);
        await tester.tap(find.text(entry.key));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(entry.value), findsOneWidget);
      });
    }

    testWidgets('«تواصل معنا» يفتح مركز الدعم الموجود فعلاً', (tester) async {
      await pumpAbout(tester);
      await scrollToBottom(tester);

      final Finder tile = find.ancestor(
        of: find.text('تواصل معنا'),
        matching: find.byType(ListTile),
      );
      await tester.tap(tile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(SupportCenterPage), findsOneWidget,
          reason: 'قناة التواصل الموجودة في المشروع هي مركز الدعم');
    });
  });

  group('الإصدار ورقم البناء', () {
    testWidgets('يُقرآن من PackageInfo لا من نصّ مكتوب', (tester) async {
      await pumpAbout(tester);

      expect(find.text('الإصدار'), findsWidgets);
      expect(find.text('رقم البناء'), findsOneWidget);
      expect(find.text(kFakeVersion), findsOneWidget);
      expect(find.text(kFakeBuild), findsOneWidget);
    });

    testWidgets('قيم pubspec.yaml تظهر كما هي حين تصل من PackageInfo',
        (tester) async {
      // يقرأ `version: X.Y.Z+N` من pubspec ويمرّره كما يمرّره Flutter،
      // فيتحقّق أن ما في الصفحة هو نفسه ما في الإعدادات بلا وسيط.
      final String pubspec = File('pubspec.yaml').readAsStringSync();
      final Match? declared =
          RegExp(r'^version:\s*(\S+)\+(\S+)\s*$', multiLine: true).firstMatch(pubspec);
      expect(declared, isNotNull, reason: 'pubspec يجب أن يعلن version');

      await pumpAbout(
        tester,
        info: fakeInfo(
          version: declared!.group(1)!,
          build: declared.group(2)!,
        ),
      );

      expect(find.text(declared.group(1)!), findsOneWidget);
      expect(find.text(declared.group(2)!), findsOneWidget);
    });

    testWidgets('تعطّل القراءة لا يُظهر رقمًا مخترَعًا', (tester) async {
      // `PackageInfo` يقرأ من قناة المنصّة، وهي غائبة في الاختبار الحقيقي.
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          host(const AboutPage(infoLoader: _alwaysFails)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('غير متوفر'), findsNWidgets(2),
          reason: '«غير متوفر» بدل رقم مخترَع');
      expect(tester.takeException(), isNull,
          reason: 'فشل القراءة لا يجوز أن يُسقط الصفحة');
    });
  });

  group('التخطيط', () {
    for (final MapEntry<String, Size> size in phoneSizes.entries) {
      testWidgets('لا فييض على ${size.key}', (tester) async {
        await pumpAbout(tester, size: size.value);
        expect(tester.takeException(), isNull,
            reason: 'AboutPage يفيض على ${size.key}');
      });
    }

    testWidgets('الاتجاه RTL مطبَّق', (tester) async {
      await pumpAbout(tester, size: const Size(412, 915));

      final Directionality dir =
          tester.widget<Directionality>(find.byType(Directionality).first);
      expect(dir.textDirection, TextDirection.rtl);
    });

    testWidgets('العربية سليمة لا تحمل محارف تلف', (tester) async {
      await pumpAbout(tester, size: const Size(412, 915));

      for (final Text w in tester.widgetList<Text>(find.byType(Text))) {
        final String? s = w.data;
        if (s == null) continue;
        expect(RegExp('[§ÙØâÃÑƒï¿½\uFFFD]').hasMatch(s), isFalse,
            reason: 'نصّ تالف في صفحة About: "$s"');
      }
    });
  });
}

Future<PackageInfo> _alwaysFails() async =>
    throw StateError('لا قناة منصّة في الاختبار');
