import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/design/app_icons.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _userId = '00000000-0000-4000-8000-000000000001';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> write({
    required String key,
    String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

void main() {
  const png = <int>[
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    20,
    8,
    6,
    0,
    0,
    0,
    99,
    247,
    163,
    32,
    0,
    0,
    0,
    45,
    73,
    68,
    65,
    84,
    120,
    218,
    99,
    172,
    232,
    89,
    192,
    64,
    75,
    192,
    68,
    83,
    211,
    25,
    70,
    45,
    32,
    3,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    64,
    16,
    140,
    90,
    192,
    64,
    8,
    0,
    0,
    0,
    11,
    71,
    1,
    204,
    161,
    53,
    60,
    254,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ];
  final requests = <http.Request>[];
  late BackendAuthSession session;
  late BackendApi api;
  late BackendAuthSession oldSession;
  late BackendApi oldApi;

  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 25));
    }
  }

  Future<void> mount(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      home: page,
    ));
    await frames(tester);
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
    oldSession = backendAuthSession;
    oldApi = backendApi;
    session = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
            jsonEncode({
              'authenticated': true,
              'access_token': 'test-access-token',
              'refresh_token': 'test-refresh-token',
              'expires_in': 3600,
              'user': {'id': _userId, 'email': 'fixture@example.com'},
            }),
            200,
            request: request,
          );
        }
        return http.Response('{}', 200, request: request);
      }),
    );
    await session.login(email: 'fixture@example.com', password: 'fixture');
    backendAuthSession = session;
    api = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendOnly: true,
      backendAccessTokenAsync: session.validAccessToken,
      backendAccessToken: () => session.accessToken,
      client: MockClient((request) async {
        requests.add(request);
        final path = request.url.path;
        if (path.endsWith('/cars/uploads/reserve')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'object_key': 'cars/$_userId/test-photo.png'},
            }),
            200,
            request: request,
          );
        }
        if (path.endsWith('/storage/object')) {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'object_key': 'cars/$_userId/test-photo.png'},
            }),
            200,
            request: request,
          );
        }
        if (request.method == 'POST' && path.endsWith('/cars')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'id': body['id']},
            }),
            201,
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

  setUp(() async {
    requests.clear();
    await Supabase.instance.client.auth.signOut(scope: SignOutScope.local);
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });

  tearDownAll(() {
    backendApi = oldApi;
    backendAuthSession = oldSession;
    api.close();
    session.dispose();
  });

  testWidgets('car section opens publish form with Backend session only',
      (tester) async {
    expect(backendAuthSession.user?.id, _userId);
    expect(Supabase.instance.client.auth.currentUser, isNull);
    await mount(
      tester,
      const SectionPage(title: kSectionCars, icon: AppIcons.cars),
    );
    await tester.tap(find.text(t('car_add')));
    await frames(tester);
    expect(find.byType(AddCarTab), findsOneWidget);
    expect(find.text(t('misc_login_first_publish')), findsNothing);
    expect(find.text(t('login_required_first')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('car listing completes with Backend session and no Supabase user',
      (tester) async {
    expect(Supabase.instance.client.auth.currentUser, isNull);
    await mount(
      tester,
      AddCarTab(
        imagePicker: () async =>
            [XFile.fromData(Uint8List.fromList(png), name: 'car.png')],
      ),
    );

    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    for (final entry in const {
      'brand': 'Toyota',
      'model': 'Camry',
      'year': '2022',
      'price': '25000',
      'phone': '07701234567',
    }.entries) {
      final field = find.byKey(ValueKey('car_${entry.key}'));
      await tester.ensureVisible(field);
      await tester.enterText(field, entry.value);
      await frames(tester);
    }
    final publish = find.text(t('misc_publish_ad'));
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await frames(tester);

    expect(find.text(t('ui_ad_submitted')), findsOneWidget);
    expect(find.text(t('login_required_first')), findsNothing);
    final protected = requests.where((request) =>
        request.url.path.endsWith('/cars/uploads/reserve') ||
        request.url.path.endsWith('/storage/object') ||
        request.method == 'POST' && request.url.path.endsWith('/cars'));
    expect(protected, hasLength(3));
    expect(
        protected.every((request) =>
            request.headers['authorization']?.startsWith('Bearer ') == true),
        isTrue);
    final listing = protected.singleWhere((request) =>
        request.method == 'POST' && request.url.path.endsWith('/cars'));
    expect(
        (jsonDecode(listing.body) as Map<String, dynamic>)['user_id'], _userId);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
