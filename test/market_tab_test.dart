import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

const Size phone = Size(360, 640);

void sizeTo(WidgetTester tester) {
  tester.view.physicalSize = phone;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

int selectedTab(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

/// The home banner runs a periodic timer, so the tree never settles and
/// `pumpAndSettle` would always time out. Pump a bounded number of frames.
Future<void> pumpFrames(WidgetTester tester, [int frames = 40]) async {
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> tapTab(WidgetTester tester, int i) async {
  await tester.tap(find.byType(NavigationDestination).at(i),
      warnIfMissed: false);
  await tester.pump();
  await pumpFrames(tester);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(
        url: supabaseUrl, publishableKey: supabaseAnonKey);
  });

  testWidgets('market tab opens its own page without pushing a route', (tester) async {
    sizeTo(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await pumpFrames(tester);
    await tapTab(tester, 2);
    expect(selectedTab(tester), 2);
    expect(find.byType(HomeTab), findsNothing);
    expect(tester.widget<SectionPage>(find.byType(SectionPage)).title, kSectionMarket);
    expect(Navigator.of(tester.element(find.byType(HomePage))).canPop(), isFalse);
    final state = tester.state(find.byType(SectionPage));
    await tapTab(tester, 2);
    expect(tester.state(find.byType(SectionPage)), same(state));
    expect(tester.takeException(), isNull);
  });

  testWidgets('market tab works from Search and Home remains distinct', (tester) async {
    sizeTo(tester);
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await pumpFrames(tester);
    await tapTab(tester, 3);
    expect(find.byType(SearchTab), findsOneWidget);
    await tapTab(tester, 2);
    expect(selectedTab(tester), 2);
    expect(tester.widget<SectionPage>(find.byType(SectionPage)).title, kSectionMarket);
    expect(find.byType(SearchTab), findsNothing);
    expect(find.byType(HomeTab), findsNothing);
    await tapTab(tester, 0);
    expect(selectedTab(tester), 0);
    expect(find.byType(HomeTab), findsOneWidget);
    expect(find.byType(SectionPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('other tabs are unchanged', (tester) async {
    sizeTo(tester);
    await tester.pumpWidget(const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    await tapTab(tester, 1);
    expect(selectedTab(tester), 1);
    expect(find.byType(SectionPage), findsOneWidget,
        reason: 'cars tab must still open the cars section page');
    expect(find.byType(HomeTab), findsNothing);

    await tapTab(tester, 3);
    expect(selectedTab(tester), 3);
    expect(find.byType(SearchTab), findsOneWidget);

    await tapTab(tester, 4);
    expect(selectedTab(tester), 4);
    expect(find.byType(AddCarTab), findsOneWidget);

    await tapTab(tester, 5);
    expect(selectedTab(tester), 5);
    expect(find.byType(AccountTab), findsOneWidget);

    await tapTab(tester, 0);
    expect(selectedTab(tester), 0);
    expect(find.byType(HomeTab), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}
