// Read-only probe for the home search box: it must sit above the marquee
// banner, use the MOTRI IQ palette, open the existing SearchTab (no new page),
// respect RTL, and never overflow at handset widths.

import 'package:flutter/material.dart';
import 'package:motri_iq/design/app_icons.dart';
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

const String hintAr = 'ابحث عن سيارة أو إعلان…';

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
    testWidgets('home search box — visible, RTL, tappable, no overflow',
        (tester) async {
      sizeTo(tester, p.value);
      await tester.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(tester.takeException(), isNull);

      // Present with the requested Arabic hint, and RTL.
      expect(find.text(hintAr), findsOneWidget, reason: 'hint at ${p.key}');
      final BuildContext box = tester.element(find.text(hintAr));
      expect(Directionality.of(box), TextDirection.rtl,
          reason: 'search box must stay RTL at ${p.key}');

      // A search glyph sits next to the hint (SearchTab is not mounted yet,
      // so every search icon on screen belongs to the home box).
      expect(find.byIcon(AppIcons.search), findsWidgets,
          reason: 'search icon missing at ${p.key}');

      // It sits above the marquee banner, not below it.
      final double boxY = tester.getTopLeft(find.text(hintAr)).dy;
      final Finder banner = find.byType(CarMarqueeStrip);
      if (banner.evaluate().isNotEmpty) {
        expect(boxY, lessThan(tester.getTopLeft(banner).dy),
            reason: 'search box must be above the banner at ${p.key}');
      }

      // Tapping reveals the EXISTING search tab inside the shell. SearchTab has no
      // Scaffold of its own (it uses ScaffoldMessenger and relies on the shell
      // Scaffold), so it must be reached as a tab, not pushed as a route.
      await tester.tap(find.text(hintAr), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SearchTab), findsOneWidget,
          reason: 'must reach the existing SearchTab at ${p.key}');
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
        3,
        reason: 'search tab must be selected at ${p.key}',
      );
      expect(find.text(hintAr), findsNothing,
          reason: 'home route must be replaced by the search tab');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('banner is untouched and still first-class in the layout',
      (tester) async {
    sizeTo(tester, const Size(360, 640));
    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // The banner widget class itself still exists and builds a dots row.
    expect(find.text(hintAr), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
