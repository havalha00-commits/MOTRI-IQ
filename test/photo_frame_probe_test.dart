// Read-only layout probe: renders every place the app shows a car picture
// (grid card, list card, compare header, gallery thumbnails, empty state) with
// CarPhoto and verifies that no frame overflows, clips, or loses its size.
// Images are intentionally absent so the shared placeholder path is exercised
// without any network access.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

Map<String, dynamic> carWith(String brand, String model) => <String, dynamic>{
      'id': '$brand-$model',
      'user_id': 'u1',
      'brand': brand,
      'model': model,
      'year': 2026,
      'price': 42000000,
      'governorate': 'بغداد',
      'fuel': 'بنزين',
      'transmission': 'أوتوماتيك',
      'mileage_km': 0,
      'description': '',
      'phone': null,
      'images': '',
      'image_url': '',
      'is_approved': true,
      'created_at': '2026-09-26T06:37:42.319744+00:00',
      'city': 'بغداد',
      'province': 'العراق',
      'body_type': 'سيدان',
      'seller_id': 'u1',
      'status': 'active',
    };

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  });

  for (final size in const <String, Size>{
    'se_320x568': Size(320, 568),
    'pixel_412x915': Size(412, 915),
  }.entries) {
    testWidgets('photo frames — no overflow at ${size.key}',
        (tester) async {
      tester.view.physicalSize = size.value;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final cars = <Map<String, dynamic>>[
        carWith('تويوتا', 'كامري ٢٠٢٦'),
        carWith('Haval', 'Jolion Pro'),
        carWith('BMW', 'X5 xDrive35d M Sport'),
      ];

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(Brightness.light),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: AppColors.scaffold,
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // بطاقة بانر
                SizedBox(
                  height: 196,
                  child: CarPhoto(urls: const [], aspectRatio: carPhotoAspect),
                ),
                // بطاقة إعلانات 4:3
                AspectRatio(
                  aspectRatio: carPhotoAspect,
                  child: CarPhoto(urls: const []),
                ),
                const SizedBox(height: 12),
                // بطاقات الشبكة
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 0.82,
                  children: [
                    for (final car in cars.take(2))
                      CarCard(car: car, square: true),
                  ],
                ),
                const SizedBox(height: 12),
                // بطاقة قائمة + مصغّرات
                for (final car in cars) CarCard(car: car),
                Row(
                  children: [
                    for (var i = 0; i < 3; i++) ...[
                      Container(
                        width: 76,
                        height: 76,
                        padding: EdgeInsets.all(i == 0 ? 2 : 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(imgRadius),
                          border: Border.all(
                            color: i == 0 ? red : AppColors.border,
                            width: i == 0 ? 2 : 1,
                          ),
                        ),
                        child: CarPhoto(
                          urls: const [],
                          radius: imgRadius - (i == 0 ? 2 : 1),
                          iconScale: 0.34,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                // صفحة التفاصيل: صورة واحدة ثم عدّاد
                CarPhoto(urls: const [], aspectRatio: carPhotoAspect),
                const SizedBox(height: 4),
                const Center(child: Text('1 / 1 صورة')),
              ],
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull, reason: 'overflow at ${size.key}');
      expect(find.byType(CarPhoto), findsWidgets);

      // كل إطار له مقاس فعلي (لا صورة نصفرية).
      for (final element in find.byType(CarPhoto).evaluate()) {
        final renderBox = element.renderObject as RenderBox?;
        expect(renderBox, isNotNull);
        expect(renderBox!.hasSize, isTrue);
        expect(renderBox.size.width, greaterThan(0));
        expect(renderBox.size.height, greaterThan(0));
      }
    });
  }
}