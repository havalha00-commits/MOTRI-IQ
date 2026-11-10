// Phone-size UI probe for the real MOTRI IQ pages.
//
// Renders the actual page widgets (SectionPage for cars/market/jobs,
// CarDetailsPage with a live-shaped row, CarCard, GenericAdCard, SectionCard,
// HomeTab) at handset viewports and fails on ANY layout exception:
// RenderFlex overflow, unbounded constraints, or RTL assertion.
//
// Read-only diagnostic. Nothing in lib/ is modified.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:package_info_plus/package_info_plus.dart';

import 'package:motri_iq/main.dart';

/// `PackageInfo` لا يُقرأ من قناة منصّة داخل الاختبار، فنغذّيه بقيم ثابتة.
Future<PackageInfo> _aboutInfo() async => PackageInfo(
      appName: 'MOTRI IQ',
      packageName: 'iq.motri',
      version: '1.0.0',
      buildNumber: '3',
    );

const Map<String, Size> phones = <String, Size>{
  'se_320x568': Size(320, 568),
  'budget_360x640': Size(360, 640),
  'pixel_412x915': Size(412, 915),
  'promax_430x932': Size(430, 932),
};

// Shape copied from a real row returned by the live API today, including the
// NULL columns, so null-safety regressions show up as layout failures.
final Map<String, dynamic> liveCar = <String, dynamic>{
  'id': '8be27116-31f3-4cc6-a747-1f52',
  'user_id': '14f652d6-e797-4c38-980c-e535c10d36b2',
  'brand': 'بي وايدي',
  'model': 'ا',
  'year': 2025,
  'price': null,
  'governorate': null,
  'fuel': null,
  'transmission': null,
  'mileage': null,
  'description': '',
  'phone': null,
  'images': '',
  'is_approved': true,
  'created_at': '2026-09-26T06:37:42.319744+00:00',
  'city': '',
  'image_url': 'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/x.jpg',
  'province': null,
  'body_type': null,
  'seller_phone': null,
  'status': 'active',
};

final Map<String, dynamic> liveMarketItem = <String, dynamic>{
  'id': 'ceec41ed-cc58-4820-b6f9-2e38',
  'user_id': '14f652d6-e797-4c38-980c-e535c10d36b2',
  'title': 'ghgh',
  'category': null,
  'price': null,
  'governorate': null,
  'description': 'gfhg',
  'phone': null,
  'images': '',
  'is_approved': true,
  'created_at': '2026-09-26T08:34:09.728171+00:00',
};

// A worst-case Arabic string: long, unbreakable-ish, to surface text overflow.
final Map<String, dynamic> longCar = <String, dynamic>{
  ...liveCar,
  'brand': 'merscedesbenzbmw',
  'model': 's63amg4maticplus',
  'description':
      'وصف طويل جداً للاختبار يحتوي على كلمات كثيرة ومطولة بدون أي مسافات قصيرة '
      'لي testing كيف يتصرف التخطيط مع نص عربي طويل جداً لا ينكسر بسهولة',
  'city': 'مدينة ذات اسم طويل جداً لاختبار التمرير',
  'governorate': 'محافظة ذات اسم طويل جداً لاختبار',
  'province': 'محافظة ذات اسم طويل جداً لاختبار',
  'body_type': 'سيارة رياضية متعددة الاستخدامات كبيرة الحجم',
};

// A row whose seller left a phone number, so the call + WhatsApp row renders.
final Map<String, dynamic> contactCar = <String, dynamic>{
  ...liveCar,
  'seller_phone': '0770 123 4567',
};

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Wraps a page so it has a Material/Directionality host, matching the app root.
Widget host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: child,
      ),
    );

void main() {
  // Pages read `supabase` in initState, so the client must exist. The key is
  // the same publishable key the app ships; no network call is made here
  // because widget tests never actually dispatch HTTP.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Supabase.initialize persists the session through shared_preferences, so
    // the in-memory store must be primed first.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabaseAnonKey,
    );
  });

  for (final p in phones.entries) {
    group('${p.key}  ${p.value.width.toInt()}x${p.value.height.toInt()}', () {
      testWidgets('SectionPage cars — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const SectionPage(
            title: 'السيارات', icon: Icons.directions_car)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'SectionPage cars overflow at ${p.key}');
      });

      testWidgets('SectionPage market — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const SectionPage(
            title: 'السوق', icon: Icons.storefront)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'SectionPage market overflow at ${p.key}');
      });

      testWidgets('CarDetailsPage — live row (mostly NULL fields)',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(CarDetailsPage(car: liveCar)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'CarDetails live row overflow at ${p.key}');
      });

      testWidgets('CarDetailsPage — worst-case long Arabic text',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(CarDetailsPage(car: longCar)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'CarDetails long text overflow at ${p.key}');
      });

      testWidgets('CarDetailsPage — seller phone, contact row fits',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(CarDetailsPage(car: contactCar)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'CarDetails contact row overflow at ${p.key}');
      });

      testWidgets('AboutPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const AboutPage(
          // `PackageInfo` يقرأ من قناة المنصّة؛ في الاختبار نمرّر مصدرًا.
          infoLoader: _aboutInfo,
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // مرّر إلى الأسفل: الروابط وحقوق النشر أسفل الطية.
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'AboutPage overflow at ${p.key}');
      });

      testWidgets('CarCard — live row, square grid cell', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              child: CarCard(car: liveCar, square: true),
            ),
          ),
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'CarCard overflow at ${p.key}');
      });

      testWidgets('GenericAdCard — market row, long title', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: ListView(
            children: [
              GenericAdCard(item: liveMarketItem, icon: Icons.storefront),
              GenericAdCard(
                icon: Icons.storefront,
                item: {
                  ...liveMarketItem,
                  'title': 'عنوان طويل جداً جداً لاختبار التفاف النص العربي',
                  'governorate': 'محافظة ذات اسم طويل',
                },
              ),
            ],
          ),
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'GenericAdCard overflow at ${p.key}');
      });

      testWidgets('SectionCard home tile — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: Column(
            children: [
              SectionCard(
                icon: Icons.directions_car,
                title: 'السيارات',
                subtitle: 'أحدث إعلانات السيارات المعروضة للبيع',
                onTap: () {},
              ),
              SectionCard(
                icon: Icons.storefront,
                title: 'السوق',
                subtitle: 'إعلانات متنوعة بين людей مع بعضهم',
                onTap: () {},
              ),
            ],
          ),
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(tester.takeException(), isNull,
            reason: 'SectionCard overflow at ${p.key}');
      });

      testWidgets('HomeTab — real page tree', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const Scaffold(body: HomeTab())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'HomeTab overflow at ${p.key}');
      });

      testWidgets('HomeTab with fontScale 1.4 (large system font)',
          (tester) async {
        sizeTo(tester, p.value);
        tester.platformDispatcher.textScaleFactorTestValue = 1.4;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await tester.pumpWidget(host(const Scaffold(body: HomeTab())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'HomeTab fontScale 1.4 overflow at ${p.key}');
      });

      // Remaining user-facing pages reachable without a session.
      testWidgets('CarRequestsPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const CarRequestsPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'CarRequestsPage overflow at ${p.key}');
      });

      testWidgets('ActivityNotificationsPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const ActivityNotificationsPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'ActivityNotificationsPage overflow at ${p.key}');
      });

      testWidgets('AlertsPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const AlertsPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'AlertsPage overflow at ${p.key}');
      });

      testWidgets('SettingsPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const SettingsPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
expect(tester.takeException(), isNull,
          reason: 'SettingsPage overflow at ${p.key}');
      });

      testWidgets('SupportCenterPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const SupportCenterPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'SupportCenterPage overflow at ${p.key}');

        // الأقسام المطلوبة كلها موجودة. العناوين تتكرّر عمدًا (عنوان قسم +
        // عنوان الخيار)، و`ListView` يبني تدريجيًا ويفكّك ما يخرج من الشاشة،
        // لذا يُتحقق من كل قسم فور ظهوره لا بعد وصول القاع.
        expect(find.text('مركز الدعم'), findsWidgets);
        expect(find.text('طريقة الحصول على المساعدة'), findsWidgets);

        Future<void> scrollStep() async {
          await tester.drag(find.byType(ListView).first, const Offset(0, -180));
          await tester.pump();
          expect(tester.takeException(), isNull,
              reason: 'SupportCenterPage overflow while scrolling ${p.key}');
        }

        for (final String section in <String>[
          'الأسئلة الشائعة',
          'الإبلاغ عن مشكلة',
          'التواصل مع الدعم',
        ]) {
          final Finder target = find.text(section);
          for (int i = 0; i < 14 && target.evaluate().isEmpty; i++) {
            await scrollStep();
          }
          expect(target, findsWidgets,
              reason: 'القسم «$section» مفقود عند ${p.key}');
        }

        // فتح سؤال شائع يجب أن يتمدّد دون تجاوز أفقي.
        final Finder firstFaq = find.text('كيف أنشر سيارة؟');
        for (int i = 0; i < 6 && firstFaq.evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -180));
          await tester.pump();
        }
        if (firstFaq.evaluate().isNotEmpty) {
          await tester.tap(firstFaq);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(tester.takeException(), isNull,
              reason: 'FAQ expansion overflow at ${p.key}');
        }

        // وأخيرًا نزّل حتى القاع للتأكد من عدم تجاوز بقية المحتوى.
        for (int i = 0; i < 10; i++) {
          await scrollStep();
        }
      });

      testWidgets('MyMessagesPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const MyMessagesPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'MyMessagesPage overflow at ${p.key}');
      });

      testWidgets('FavoritesPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const FavoritesPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'FavoritesPage overflow at ${p.key}');
      });

      testWidgets('MyReviewsPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const MyReviewsPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'MyReviewsPage overflow at ${p.key}');
      });

      testWidgets('ManageShowroomPage — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const ManageShowroomPage()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'ManageShowroomPage overflow at ${p.key}');
      });

      testWidgets('AddCarTab — publish form, no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const Scaffold(body: AddCarTab())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'AddCarTab overflow at ${p.key}');
      });

      testWidgets('SearchTab — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const Scaffold(body: SearchTab())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'SearchTab overflow at ${p.key}');
      });

      testWidgets('AccountTab — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(const Scaffold(body: AccountTab())));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull,
            reason: 'AccountTab overflow at ${p.key}');
      });

      // AccountTab في الاختبارات يُبنى بحالة غير مسجّل، فلا تُبنى صفوف
      // `_accountRow`. الفحصان التاليان يغطّيان تركيبها:
      //  1) بالشكل المُصلَح — يجب ألا يُبلَّغ عن أي استثناء.
      //  2) بالشكل المُسبِّب للخطأ — يجب أن يُبلَّغ عن تأكيد Flutter، وهو
      //     ما يثبت أن الحارس هنا حيّ وليس فحصًا فارغًا.
      testWidgets('AccountTab row tile — no ink assert (fixed shape)',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: Colors.black12)),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(17),
              clipBehavior: Clip.antiAlias,
              child: const ListTile(
                leading: Icon(Icons.person_outline, color: Colors.black87),
                title: Text('الملف الشخصي',
                    style: TextStyle(
                        color: Colors.black87, fontWeight: FontWeight.w700)),
                trailing: Icon(Icons.chevron_left, color: Colors.black45),
              ),
            ),
          ),
        )));
        await tester.pump();
        expect(tester.takeException(), isNull,
            reason: 'account row ink assert (fixed) at ${p.key}');
      });

      testWidgets('AccountTab row tile — colored wrapper still trips assert',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: Container(
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(17)),
            child: ListTile(
              onTap: () {},
              title: Text('الملف الشخصي', textDirection: TextDirection.rtl),
            ),
          ),
        )));
        await tester.pump();
        final err = tester.takeException();
        expect(err, isNotNull,
            reason: 'assert should be live at ${p.key} — if this fails, '
                'the SDK no longer warns and the fix is no longer required');
        expect('$err', contains('may be invisible'));
      });

      testWidgets('CarMarqueeStrip — marquee banner, no overflow',
          (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(host(Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 138,
                child: CarMarqueeStrip(
                  cars: [liveCar, longCar, liveMarketItem],
                ),
              ),
            ],
          ),
        )));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull,
            reason: 'CarMarqueeStrip overflow at ${p.key}');
      });
    });
  }
}