// اختبارات خفيفة لوظائف بيانات خالصة في MOTRI IQ.
//
// هذه الدوال لا تستدعي Supabase ولا الشبكة، لذلك تعمل داخل
// WidgetTesterBinding العادي بلا تهيئة أي جلسة.
//
// ملف الاختبار الافتراضي القديم (counter + MyApp) حُذف: MOTRI IQ لا يحتوي
// `MyApp` ولا عدّادًا، فكان الاختبار يفشل بالتصميم.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motri_iq/main.dart';
import 'package:motri_iq/market_images.dart';

void main() {
  group('badgeLabel', () {
    test('يرجّع التسمية العربية لكل نوع بائع', () {
      expect(badgeLabel('gold'), 'ذهبي');
      expect(badgeLabel('silver'), 'فضي');
      expect(badgeLabel('bronze'), 'نحاسي');
    });

    test('يرجّع نصًا فارغًا لنوع غير معروف أو فارغ', () {
      expect(badgeLabel('platinum'), '');
      expect(badgeLabel(''), '');
    });
  });

  group('badgeColor', () {
    test('يرجّع لونًا مختلفًا لكل نوع معروف', () {
      expect(badgeColor('gold'), const Color(0xFFFFD700));
      expect(badgeColor('silver'), const Color(0xFFC0C0C0));
      expect(badgeColor('bronze'), const Color(0xFFCD7F32));
    });

    test('يرجّع لونًا احتياطيًا لنوع غير معروف', () {
      expect(badgeColor('platinum'), AppColors.textHint);
    });
  });

  group('carImageUrls', () {
    test('يرجّع قائمة فارغة عندما لا يوجد عمود image_url', () {
      expect(carImageUrls({'id': 1}), isEmpty);
    });

    test('يرجّع قائمة فارغة لنص فارغ أو مسافات فقط', () {
      expect(carImageUrls({'image_url': ''}), isEmpty);
      expect(carImageUrls({'image_url': '   '}), isEmpty);
    });

    test('يرجّع الرابط كما هو إذا لم يكن JSON', () {
      expect(carImageUrls({'image_url': 'https://x.test/a.jpg'}),
          ['https://x.test/a.jpg']);
    });

    test('يفكّ مصفوفة JSON ويتجاهل العناصر الفارغة', () {
      final urls = carImageUrls({
        'image_url': '["https://x.test/a.jpg", "", "https://x.test/b.jpg"]',
      });
      expect(urls, ['https://x.test/a.jpg', 'https://x.test/b.jpg']);
    });

    test('يربط مسارات صور API بعنوان Backend', () {
      const path = '/api/cars/00000000-0000-4000-8000-000000000001/images/0';
      expect(
        carImageUrls({
          'image_urls': [path]
        }),
        [Uri.parse(backendUrl).resolve(path).toString()],
      );
    });

    test('لا يرمي استثناءً على JSON تالف', () {
      expect(carImageUrls({'image_url': '[not json'}), ['[not json']);
    });
  });

  group('حدود صور إعلان السوق', () {
    test('الحد الأدنى صورتان والحد الأعلى 6', () {
      expect(kMarketMinImages, 2);
      expect(kMarketMaxImages, 6);
      expect(kMarketMinImages, lessThan(kMarketMaxImages));
    });
  });

  group('marketItemImageUrls', () {
    test('يرجّع قائمة فارغة عندما لا يوجد عمود images', () {
      expect(marketItemImageUrls({'id': 1}), isEmpty);
    });

    test('يقرأ قائمة روابط مباشرة', () {
      final urls = marketItemImageUrls({
        'images': ['https://x.test/1.jpg', 'https://x.test/2.jpg'],
      });
      expect(urls.length, 2);
      expect(urls.first, 'https://x.test/1.jpg');
    });

    test('يقرأ نص JSON يبدأ بقوس مفتوح', () {
      final urls = marketItemImageUrls({
        'images': '["https://x.test/1.jpg"]',
      });
      expect(urls, ['https://x.test/1.jpg']);
    });
  });

  group('sellerBadge', () {
    testWidgets('لا يبني شيئًا لنوع فارغ أو none', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
          sellerBadge('', 24),
          sellerBadge('none', 24),
        ])),
      ));

      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('يبني Tooltip لنوع معروف', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: sellerBadge('gold', 24)),
      ));

      expect(find.byType(Tooltip), findsOneWidget);
    });
  });
}
