import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

void main() {
  late BackendApi previousApi;
  late BackendApi api;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'test',
      httpClient: MockClient((request) async => http.Response('[]', 200,
          request: request, headers: {'content-type': 'application/json'})),
    );
    previousApi = backendApi;
  });

  setUp(() {
    api = BackendApi(
      baseUrl: 'https://backend.example.test',
      client: MockClient((request) async => http.Response(
            '{"success":true,"data":[]}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          )),
    );
    backendApi = api;
  });

  tearDown(() {
    api.close();
    backendApi = previousApi;
  });

  testWidgets('empty home sections disappear and market tab remains reachable',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 30));
    }
    final list = find
        .descendant(of: find.byType(HomeTab), matching: find.byType(ListView))
        .first;
    await tester.drag(list, const Offset(0, -1800));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(t('home_most_requested')), findsNothing);
    expect(find.text(t('ad_new')), findsNothing);
    expect(find.text(t('home_latest_suggestions')), findsNothing);
    expect(find.text(t('home_recent_ads')), findsNothing);
    expect(find.text(t('home_saved_with_you')), findsNothing);
    expect(find.text(t('home_latest_market')), findsNothing);
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(2);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(HomeTab), findsNothing);
    final market = tester.widget<SectionPage>(find.byType(SectionPage));
    expect(market.title, kSectionMarket);
    expect(market.key, const ValueKey('market_tab'));
    // Repeated taps must keep the same page state rather than opening a copy.
    final marketState = tester.state(find.byType(SectionPage));
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(2);
    await tester.pump();
    expect(tester.state(find.byType(SectionPage)), same(marketState));
    expect(find.byType(HomePage), findsOneWidget);
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(1);
    await tester.pump();
    expect(tester.widget<SectionPage>(find.byType(SectionPage)).title,
        kSectionCars);
    expect(tester.state(find.byType(SectionPage)), isNot(same(marketState)));
    expect(find.byType(HomeTab), findsNothing);
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(0);
    await tester.pump();
    expect(find.text(t('home_latest_market')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
