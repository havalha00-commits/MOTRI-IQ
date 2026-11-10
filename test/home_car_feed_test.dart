import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final homeCarsRequests = <http.Request>[];
  late BackendApi previousApi;
  late BackendApi api;

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 3)));
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient(
          (request) async => http.Response('{}', 200, request: request)),
    );
    previousApi = backendApi;
  });

  setUp(() {
    homeCarsRequests.clear();
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
    carGridLayoutNotifier.value = true;
    api = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendOnly: true,
      backendAccessToken: () => null,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/cars')) {
          homeCarsRequests.add(request);
          final offset =
              int.parse(request.url.queryParameters['offset'] ?? '0');
          final cars = offset >= 40
              ? <Map<String, dynamic>>[]
              : List<Map<String, dynamic>>.generate(
                  20,
                  (index) => {
                    'id': 'home-car-${offset + index}',
                    'brand': 'Toyota',
                    'model': 'Corolla ${offset + index}',
                    'year': 2024,
                    'price': 10000,
                    'images': <String>[],
                    'image_urls': <String>[],
                  },
                );
          return http.Response(
            jsonEncode({'success': true, 'data': cars}),
            200,
            request: request,
          );
        }
        return http.Response(
          jsonEncode({'success': true, 'data': <dynamic>[]}),
          200,
          request: request,
        );
      }),
    );
    backendApi = api;
  });

  tearDown(() {
    api.close();
    backendApi = previousApi;
  });

  testWidgets('home car feed requests additional pages as the user scrolls',
      (tester) async {
    tester.view.physicalSize = const Size(390, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: appLocale.locale,
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      home: Scaffold(
        body: HomeTab(
          scrollController: controller,
          marketSelected: ValueNotifier<bool>(false),
        ),
      ),
    ));
    await frames(tester);

    expect(
      homeCarsRequests
          .any((request) => request.url.queryParameters['offset'] == '0'),
      isTrue,
    );
    expect(find.text('Toyota Corolla 0'), findsOneWidget);
    controller.jumpTo(controller.position.maxScrollExtent);
    await frames(tester);

    expect(
      homeCarsRequests
          .any((request) => request.url.queryParameters['offset'] == '20'),
      isTrue,
    );
    carGridLayoutNotifier.value = false;
    await tester.pump();
    expect(
      find.byWidgetPredicate((widget) => widget is CarCard && !widget.square),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('car listing layout preference persists', () async {
    SharedPreferences.setMockInitialValues({});
    carGridLayoutNotifier.value = true;

    await setCarGridLayout(false);

    final prefs = await SharedPreferences.getInstance();
    expect(carGridLayoutNotifier.value, isFalse);
    expect(prefs.getBool('motri.cars.grid_layout'), isFalse);
  });
}
