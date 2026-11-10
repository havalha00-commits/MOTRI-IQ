// اختبار زرّ «التواصل مع الدعم» في مركز الدعم.
//
// العقد: الخيار نفسه موجود كما هو، وتغيّرت وظيفته فقط — يفتح ورقةً تعرض
// واتساب واتصال لرقم الدعم `07715339922`، وواتساب يخرج بالصيغة الدولية
// `9647715339922` بلا `+` ولا مسافات.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';

const Map<String, Size> phoneSizes = <String, Size>{
  'se_320x568': Size(320, 568),
  'pixel_412x915': Size(412, 915),
};

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

Future<void> pumpSupportCenter(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(const SupportCenterPage()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.scrollUntilVisible(supportOption, 250,
      scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Finder get supportOption => find.ancestor(
      of: find.text('التواصل مع الدعم'),
      matching: find.byType(ListTile),
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

  tearDown(() => appLocaleNotifier.value = AppLocale.ar);

  group('روابط رقم الدعم', () {
    test('واتساب بالصيغة الدولية بلا + ولا مسافات', () {
      expect(kSupportPhone, '07715339922');
      expect(supportWhatsAppUri().toString(), 'https://wa.me/9647715339922');
      expect(supportWhatsAppUri().path, '/9647715339922');
    });

    test('الاتصال بالرقم المحلي كما هو', () {
      expect(supportCallUri().toString(), 'tel:07715339922');
      expect(supportCallUri().scheme, 'tel');
      expect(supportCallUri().path, '07715339922');
    });
  });

  group('الواجهة', () {
    testWidgets('الخيار ما زال في مكانه ولم يتغيّر نصّه', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));

      expect(supportOption, findsOneWidget);
      final ListTile tile = tester.widget<ListTile>(supportOption);
      expect(tile.title, isA<Text>());
      expect((tile.title as Text).data, 'التواصل مع الدعم');
      expect(tile.onTap, isNotNull, reason: 'الخيار يجب أن يبقى قابلًا للضغط');
    });

    testWidgets('الضغط عليه يعرض واتساب واتصال ورقم الدعم', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));

      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('واتساب الآن'), findsOneWidget);
      expect(find.text('اتصل'), findsOneWidget);
      expect(find.text(kSupportPhone), findsOneWidget,
          reason: 'الرقم معروض كما هو ليتحقّق المستخدم قبل الضغط');
      expect(tester.takeException(), isNull,
          reason: 'فتح الورقة لا يجوز أن يرمي استثناء');
    });

    testWidgets('لا فييض على 320 بكسل', (tester) async {
      await pumpSupportCenter(tester, const Size(320, 568));
      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull,
          reason: 'الورقة تفيض على شاشة 320 بكسل');
      expect(find.text('واتساب الآن'), findsOneWidget);
    });

    testWidgets('اختيار «اتصل» يغلق الورقة بلا Crash', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));
      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(OutlinedButton, 'اتصل'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // `launchUrl` يرمي في الاختبار (لا قناة منصّة)؛ المطلوب ألّا يسقط ذلك
      // الصفحة، فتبقى الورقة مغلقة وتظهر رسالة بدل انهيار.
      expect(tester.takeException(), isNull,
          reason: 'فشل فتح تطبيق الهاتف لا يجوز أن يُسقط مركز الدعم');
      expect(find.text('واتساب الآن'), findsNothing);
      expect(find.byType(SupportCenterPage), findsOneWidget);
    });

    testWidgets('اختيار «واتساب» يغلق الورقة بلا Crash', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));
      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.widgetWithText(OutlinedButton, 'واتساب الآن'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.takeException(), isNull);
      expect(find.byType(SupportCenterPage), findsOneWidget);
    });

    testWidgets('الإلغاء لا يفعل شيئًا', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));
      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // الضغط على الخلفية يغلق الورقة دون اختيار.
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('واتساب الآن'), findsNothing);
      expect(find.byType(SupportCenterPage), findsOneWidget);
    });
  });

  group('العربية والاتجاه', () {
    testWidgets('الأوراق نصّها سليم و RTL', (tester) async {
      await pumpSupportCenter(tester, const Size(412, 915));
      await tester.tap(supportOption);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final Iterable<Text> texts = tester.widgetList<Text>(find.byType(Text));
      final Iterable<String> arabic =
          texts.map((Text w) => w.data ?? '').where((String s) => s.isNotEmpty);
      expect(arabic, isNotEmpty);
      for (final String s in arabic) {
        expect(RegExp('[§ÙØâÃÑƒï¿½\uFFFD]').hasMatch(s), isFalse,
            reason: 'نصّ تالف في مركز الدعم: "$s"');
      }

      final Directionality dir =
          tester.widget<Directionality>(find.byType(Directionality).first);
      expect(dir.textDirection, TextDirection.rtl);
    });
  });

  group('المقاسات', () {
    for (final MapEntry<String, Size> size in phoneSizes.entries) {
      testWidgets('مركز الدعم والورقة بلا فييض على ${size.key}',
          (tester) async {
        await pumpSupportCenter(tester, size.value);
        expect(tester.takeException(), isNull);

        await tester.tap(supportOption);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull, reason: 'فييض على ${size.key}');
      });
    }
  });
}
