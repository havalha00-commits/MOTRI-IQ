// Temporary read-only probe: renders the REAL HomePage shell (the one whose
// bottom NavigationBar was changed) at handset viewports and fails on ANY
// layout exception: RenderFlex overflow, unbounded constraints, or RTL
// assertion. Also asserts all 6 destinations exist and are laid out inside the
// bar. Nothing in lib/ is modified.

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
    group('${p.key}  ${p.value.width.toInt()}x${p.value.height.toInt()}', () {
      testWidgets('HomePage shell + 6-tab nav — no overflow', (tester) async {
        sizeTo(tester, p.value);
        await tester.pumpWidget(const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: HomePage(),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        expect(tester.takeException(), isNull,
            reason: 'HomePage nav overflow at ${p.key}');

        final NavigationBar bar = tester.widget(find.byType(NavigationBar));
        expect(bar.destinations.length, 6,
            reason: 'expected 6 destinations at ${p.key}');
        expect(
          bar.destinations
              .map((Widget w) => (w as NavigationDestination).label)
              .toList(),
          <String>['الرئيسية', 'السيارات', 'السوق', 'البحث', 'إضافة', 'حسابي'],
          reason: 'tab order/labels at ${p.key}',
        );

        for (int i = 0; i < 6; i++) {
          await tester.tap(find.byType(NavigationDestination).at(i));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          expect(tester.takeException(), isNull,
              reason: 'tab $i overflow at ${p.key}');
          expect(
            tester.widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            i,
            reason: 'tab $i did not become selected at ${p.key}',
          );
        }
      });
    });
  }

  testWidgets('nav label font keeps a readable narrow-phone minimum', (tester) async {
    Future<double> labelSizeFor(double width) async {
      sizeTo(tester, Size(width, 800));
      await tester.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: HomePage(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final NavigationBar bar = tester.widget(find.byType(NavigationBar));
      final style = bar.labelTextStyle!.resolve(<WidgetState>{})!;
      expect(tester.takeException(), isNull);
      return style.fontSize ?? 0;
    }

    expect(await labelSizeFor(900), 12.0, reason: 'wide screen keeps 12');
    expect(await labelSizeFor(320), 11.0, reason: '320 retains readable labels');
    expect(await labelSizeFor(360), lessThan(12.0), reason: '360 shrinks');
  });
}
