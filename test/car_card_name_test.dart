// Read-only probe: the full-width CarCard used on the home page now renders the
// car name on up to two lines, with the paragraph direction derived from the
// name itself. Verifies no overflow for pathological names in both script
// directions, at handset widths.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

const Map<String, Size> phones = <String, Size>{
  'se_320x568': Size(320, 568),
  'budget_360x640': Size(360, 640),
  'pixel_412x915': Size(412, 915),
  'promax_430x932': Size(430, 932),
};

const Map<String, Map<String, String>> cases = <String, Map<String, String>>{
  // Latin names: the reported "...Haval" / "...Geely" / "...BYD So" case.
  'latin_short': <String, String>{'brand': 'Haval', 'model': 'Jolion'},
  'latin_long': <String, String>{
    'brand': 'merscedesbenzbmw',
    'model': 's63amg4maticplus',
  },
  'latin_byd': <String, String>{
    'brand': 'BYD',
    'model': 'Song Plus Premium Extended Range',
  },
  // Arabic names must stay RTL.
  'arabic': <String, String>{'brand': 'تويوتا', 'model': 'كامري ٢٠٢٦'},
  // Mixed script must not throw.
  'mixed': <String, String>{'brand': 'هيونداي', 'model': 'Tucson Hybrid'},
};

Map<String, dynamic> carWith(String brand, String model) => <String, dynamic>{
      'id': 'c1',
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
      'image_url':
          'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/x.jpg',
      'is_approved': true,
      'created_at': '2026-09-26T06:37:42.319744+00:00',
      'city': 'بغداد',
      'province': 'العراق',
      'body_type': 'سيدان',
      'seller_id': 'u1',
      'status': 'active',
    };

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  });

  for (final p in phones.entries) {
    for (final c in cases.entries) {
      testWidgets('full-width CarCard — ${c.key} at ${p.key}', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(useMaterial3: true),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: ListView(
                children: <Widget>[
                  CarCard(car: carWith(c.value['brand']!, c.value['model']!)),
                  CarCard(car: carWith(c.value['brand']!, c.value['model']!)),
                ],
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull,
            reason: 'overflow for ${c.key} at ${p.key}');

        // The name is present and laid out (never dropped).
        final String name = '${c.value['brand']} ${c.value['model']}'.trim();
        expect(find.text(name), findsNWidgets(2),
            reason: 'name missing for ${c.key} at ${p.key}');
      });
    }
  }
}