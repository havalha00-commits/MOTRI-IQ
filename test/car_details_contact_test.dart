// اختبار زرَّي «اتصال» و«واتساب» في صفحة تفاصيل السيارة.
//
// العقد الذي يفحصه هذا الملف: الزرّان يظهران معًا حين يوجد رقم صالح،
// ويختفيان معًا حين لا يوجد — ولا يظهر زرٌّ يفتح صفحة خطأ.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

/// إعلان برقم هاتف محدَّد. `seller_phone` هو العمود الذي تكتبه صفحة الإضافة.
Map<String, dynamic> carWithPhone(Object? phone) => <String, dynamic>{
      'id': 'car-1',
      'user_id': 'seller-1',
      'brand': 'Nissan',
      'model': 'Patrol',
      'year': 2022,
      'price': '100',
      'description': '',
      'images': '',
      'province': 'بغداد',
      'seller_phone': phone,
    };

/// `ListView` في صفحة التفاصيل يبني ما في الشاشة فقط، فبطاقة البائع
/// وازراها أسفل الصورة ولا تُبنى قبل التمرير. لذلك كل فحص — ظهور أو غياب —
/// يبدأ من نفس الموضع، وإلا صار الفحص يمرّ على عنصر لم يُبنَ أصلًا.
Future<void> scrollToContactRow(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -900));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> pumpDetails(WidgetTester tester, Map<String, dynamic> car) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(host(CarDetailsPage(car: car)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await scrollToContactRow(tester);
}

Widget host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    );

/// الزرّان معًا: لا معنى لاختبار أحدهما منفردًا، فالقرار واحد.
Matcher get bothContactButtons =>
    findsNWidgets(2);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  });

  group('الزرّان يظهران', () {
    testWidgets('إعلان فيه رقم عراقي يعرض زرَّي الاتصال والواتساب',
        (tester) async {
      await pumpDetails(tester, carWithPhone('07701234567'));

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsOneWidget);
    });

    testWidgets('رقم بمسافات وشرطات يُقبل كما هو', (tester) async {
      await pumpDetails(tester, carWithPhone('+964 770 123 4567'));

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsOneWidget);
    });

    testWidgets('العمود القديم `phone` يُقرأ احتياطيًّا', (tester) async {
      // إعلان قديم كُتب فيه الرقم في `phone` قبل وجود `seller_phone`.
      await pumpDetails(
          tester, carWithPhone(null)..['phone'] = '07701234567');

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsOneWidget);
    });

    testWidgets('الزرّان يأخذان نصف العرض ولا يطفحان', (tester) async {
      await pumpDetails(tester, carWithPhone('07701234567'));

      expect(tester.takeException(), isNull,
          reason: 'صفّ الازرين لا يجوز أن يفيض على شاشة 412 بكسل');
      expect(find.byType(OutlinedButton), bothContactButtons);
    });
  });

  group('الزرّان يختفيان', () {
    testWidgets('إعلان بلا هاتف لا يعرض أي زر', (tester) async {
      await pumpDetails(tester, carWithPhone(null));

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsNothing);
    });

    testWidgets('رقم غير صالح لا يعرض أي زر', (tester) async {
      await pumpDetails(tester, carWithPhone('اتصل بي'));

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsNothing);
    });

    testWidgets('رقم ناقص جدًّا لا يعرض أي زر', (tester) async {
      await pumpDetails(tester, carWithPhone('123'));

      expect(find.widgetWithText(OutlinedButton, 'اتصل'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'واتساب الآن'), findsNothing);
    });
  });
}
