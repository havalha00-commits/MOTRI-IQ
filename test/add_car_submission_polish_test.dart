import 'dart:async';
import 'dart:ui' as ui;
import 'support/current_typography_checkpoint.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:image_picker/image_picker.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';

const uid = '00000000-0000-4000-8000-000000000001';

class _MemoryStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    AppleOptions? mOptions,
    WebOptions? webOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
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
      _values[key];

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
    _values.remove(key);
  }
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  final writes = <http.Request>[];
  Completer<void>? gate, uploadGate, pickerGate;
  final uploads = <http.Request>[];
  var failUploadAt = 0, pickCalls = 0, pickerFails = false;
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAACAAAAAUCAIAAABj86gYAAAALUlEQVR4nGOs6FnAQEvARFPTGUYtIAKMWkAQjFpAEIxaQBCMWkAQjFrAQAgAAAtHAcyhNTz+AAAAAElFTkSuQmCC');
  late List<XFile> photos;
  var photoBytes = png;
  var photoName = 'car.png';
  var noAck = false, fail = false, wrongAck = false;
  var missingPlateRegions = false;
  late BackendAuthSession oldBackendAuthSession;
  late BackendApi oldBackendApi;
  late BackendAuthSession testBackendAuthSession;
  late BackendApi testBackendApi;

  Future<void> signOutAccount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await backendAuthSession.logout();
      await supabase.auth.signOut(scope: SignOutScope.local);
    });
  }

  Future<void> signInAccount(WidgetTester tester) async {
    await tester.runAsync(() async {
      await supabase.auth.signInWithPassword(
        email: 'fixture@example.com',
        password: 'fixture',
      );
      await backendAuthSession.login(
        email: 'fixture@example.com',
        password: 'fixture',
      );
    });
  }

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      final response = await http
          .get(Uri.parse(
              'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg'))
          .timeout(const Duration(seconds: 25));
      expect(response.statusCode, 200);
      expect(response.bodyBytes.length, greaterThan(1000));
      photoBytes = response.bodyBytes;
      photoName = 'car.jpg';
    }

    oldBackendAuthSession = backendAuthSession;
    oldBackendApi = backendApi;
    final token = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': uid,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    final signature = base64Url.encode(List.filled(32, 0)).replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((req) async {
          Object? body = [];
          var status = 200;
          if (req.url.path == '/auth/v1/token') {
            body = {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$token.$signature',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
          } else if (req.url.path == '/auth/v1/logout') {
            body = {};
          }
          return http.Response(jsonEncode(body), status,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    testBackendAuthSession = BackendAuthSession(
      baseUrl: 'https://backend.example.test',
      storage: _MemoryStorage(),
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'authenticated': true,
              'access_token': 'fixture-access-token',
              'refresh_token': 'fixture-refresh-token',
              'expires_in': 3600,
              'user': {
                'id': uid,
                'email': 'fixture@example.com',
                'is_admin': false,
              },
            }),
            200,
            request: request,
          )),
    );
    await testBackendAuthSession.login(
      email: 'fixture@example.com',
      password: 'fixture',
    );
    backendAuthSession = testBackendAuthSession;
    testBackendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      backendOnly: true,
      backendAccessTokenAsync: testBackendAuthSession.validAccessToken,
      backendAccessToken: () => testBackendAuthSession.accessToken,
      client: MockClient((request) async {
        final path = request.url.path;
        if (path.endsWith('/cars/uploads/reserve')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final objectKey =
              'cars/$uid/${body['submission_id']}/${body['photo_id']}.${body['extension']}';
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {'object_key': objectKey},
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (path.endsWith('/storage/object')) {
          uploads.add(request);
          await uploadGate?.future;
          if (failUploadAt == uploads.length) {
            return http.Response(
              '{"message":"private upload detail"}',
              400,
              request: request,
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'object_key': request.url.queryParameters['path'],
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.method == 'POST' && path.endsWith('/cars')) {
          writes.add(request);
          if (gate != null) await gate!.future;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (missingPlateRegions && body.containsKey('plate_regions')) {
            return http.Response(
              jsonEncode({
                'message':
                    "Could not find the 'plate_regions' column of 'cars' in the schema cache",
                'code': 'PGRST204',
              }),
              400,
              request: request,
            );
          }
          if (fail) {
            return http.Response(
              '{"message":"private database detail","code":"XX000"}',
              500,
              request: request,
            );
          }
          return http.Response(
            jsonEncode({
              'success': true,
              'data': noAck
                  ? []
                  : {
                      'id': wrongAck ? 'other-offer' : body['id'],
                    },
            }),
            201,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('{"error":"not found"}', 404, request: request);
      }),
    );
    backendApi = testBackendApi;
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(
          email: 'fixture@example.com', password: 'fixture');
    }
    if (backendAuthSession.user == null) {
      await backendAuthSession.login(
        email: 'fixture@example.com',
        password: 'fixture',
      );
    }
    writes.clear();
    gate = uploadGate = pickerGate = null;
    uploads.clear();
    failUploadAt = 0;
    pickCalls = 0;
    pickerFails = false;
    photos = [XFile.fromData(photoBytes, name: photoName)];
    noAck = fail = wrongAck = missingPlateRegions = false;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  tearDownAll(() async {
    await supabase.auth.signOut(scope: SignOutScope.local);
    await backendAuthSession.logout();
    backendApi = oldBackendApi;
    backendAuthSession = oldBackendAuthSession;
    testBackendApi.close();
    testBackendAuthSession.dispose();
  });
  Future<List<XFile>> pick() async {
    pickCalls++;
    await pickerGate?.future;
    if (pickerFails) throw StateError('private picker detail');
    return photos;
  }

  Future<void> mount(WidgetTester tester,
      {double scale = 1.6, double width = 360}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = Size(width, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(AppStringsScope(
        locale: appLocale,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(
                AppColors.isDark ? Brightness.dark : Brightness.light),
            locale: appLocale.locale,
            supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
            localizationsDelegates: appLocalizationsDelegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: AddCarTab(imagePicker: pick))));
    await frames(tester);
  }

  Finder field(String key) => find.byKey(ValueKey('car_$key'));
  Future<void> reveal(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await frames(tester);
    final scroll = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await frames(tester);
    await tester.scrollUntilVisible(target, 220,
        scrollable: scroll, maxScrolls: 60);
    await frames(tester);
  }

  Future<void> input(WidgetTester tester, String key, String text) async {
    await reveal(tester, field(key));
    await tester.tap(field(key));
    await frames(tester);
    await tester.enterText(field(key), text);
    await frames(tester);
    expect(tester.widget<TextFormField>(field(key)).controller!.text, text);
  }

  Future<void> draft(WidgetTester tester) async {
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await frames(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    await input(tester, 'brand', 'Toyota');
    await input(tester, 'model', 'Land Cruiser');
    await input(tester, 'year', '٢٠٢٤');
    await input(tester, 'price', '٣٤٬٥٠٠٫٥');
    await input(tester, 'phone', '07701234567');
    await input(tester, 'description', 'Retained vehicle description');
  }

  Future<void> submit(WidgetTester tester) async {
    await reveal(tester, find.text(t('misc_publish_ad')));
    await tester.tap(find.text(t('misc_publish_ad')));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> hold(WidgetTester tester, String marker) async {
    if (!const bool.fromEnvironment('UI_ADDCAR_REVIEW_HOLD')) return;
    debugPrint(marker);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Add Car photo actions ${locale.code} dark=$dark accessible',
          (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          await mount(tester, width: 320);
          final initial =
              tester.getSemantics(find.bySemanticsLabel(t('car_add_images')));
          expect(initial.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(initial.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          initial.owner!.performAction(initial.id, ui.SemanticsAction.tap);
          await frames(tester);
          expect(pickCalls, 1);
          expect(find.text('1 / 1'), findsOneWidget);
          final moreFinder = find.bySemanticsLabel(t('ui_add_photos'));
          await tester.ensureVisible(moreFinder);
          await frames(tester);
          final more = tester.getSemantics(moreFinder);
          expect(more.getSemanticsData().flagsCollection.isButton, isTrue);
          expect(more.getSemanticsData().hasAction(ui.SemanticsAction.tap),
              isTrue);
          photos = [];
          more.owner!.performAction(more.id, ui.SemanticsAction.tap);
          await frames(tester);
          expect(pickCalls, 2);
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await frames(tester);
          expect(find.text('1 / 1'), findsOneWidget);
          expect(uploads, isEmpty);
          expect(writes, isEmpty);
          await finish(tester);
        } finally {
          semantics.dispose();
        }
      });
      testWidgets('Add Car city action ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester, width: 320);
        await reveal(tester, field('city'));
        final action = find.byTooltip(t('settings_location'));
        expect(
            (tester.getCenter(field('city')).dy - tester.getCenter(action).dy)
                .abs(),
            lessThan(1));
        expect(tester.getSize(action).shortestSide, greaterThanOrEqualTo(48));
        await currentTypographyCheckpoint(tester, 'ADD_CAR_CITY');
        expect(uploads, isEmpty);
        expect(writes, isEmpty);
        await finish(tester);
      });
      testWidgets(
          'Add Car ${locale.code} dark=$dark enlarged failed submission and retained photo',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        fail = true;
        await mount(tester);
        for (final key in ['brand', 'model', 'city', 'description']) {
          await reveal(tester, field(key));
          final controller =
              tester.widget<TextFormField>(field(key)).controller!;
          for (final sample in ['Toyota خدمة', 'خدمة Toyota']) {
            final value = TextEditingValue(
                text: sample,
                selection: const TextSelection.collapsed(offset: 2),
                composing: const TextRange(start: 0, end: 2));
            controller.value = value;
            await tester.pump();
            final input = find.descendant(
                of: field(key), matching: find.byType(TextField));
            expect(
                tester.widget<TextField>(input).textDirection,
                sample.startsWith('Toyota')
                    ? TextDirection.ltr
                    : TextDirection.rtl);
            expect(controller.value, value);
          }
          controller.clear();
        }
        for (final key in ['year', 'price', 'phone']) {
          await reveal(tester, field(key));
          final input =
              find.descendant(of: field(key), matching: find.byType(TextField));
          expect(
              tester.widget<TextField>(input).textDirection, TextDirection.ltr);
        }
        await reveal(tester, field('brand'));
        await currentTypographyCheckpoint(tester, 'ADD_CAR_FORM');
        await draft(tester);
        await submit(tester);
        expect(find.textContaining(t('ui_ad_publish_failed')), findsOneWidget);
        expect(find.textContaining('500'), findsOneWidget);
        expect(find.textContaining('private'), findsNothing);
        expect(uploads.length, 1);
        expect(writes.length, 1);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text(t('misc_publish_ad')).hitTestable(), findsOneWidget,
            reason: 'Retry action remains visible after failure');
        await currentTypographyCheckpoint(tester, 'ADD_CAR_RECOVERY');
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'ADDCAR_ERROR_${locale.code.toUpperCase()}');
        }
        await reveal(tester, field('brand'));
        expect(tester.widget<TextFormField>(field('brand')).controller!.text,
            'Toyota');
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
        await frames(tester);
        expect(find.byType(Image), findsWidgets);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'ADD_CAR_MEDIA');
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'ADDCAR_PHOTO_${locale.code.toUpperCase()}');
        }
        await finish(tester);
      });
    }
  }
  for (final failure in ['server', 'no_ack', 'wrong_ack']) {
    testWidgets('Add Car $failure retry reuses uploaded media and listing id',
        (tester) async {
      fail = failure == 'server';
      noAck = failure == 'no_ack';
      wrongAck = failure == 'wrong_ack';
      await mount(tester);
      await draft(tester);
      await submit(tester);
      final first = jsonDecode(writes.single.body);
      expect(first['title'], 'Toyota Land Cruiser');
      expect(first['phone'], '07701234567');
      expect(first['seller_phone'], '07701234567');
      expect(first['year'], 2024);
      expect(first['price'], 34500.5);
      expect(first['user_id'], uid);
      expect(jsonDecode(first['image_url']), hasLength(1));
      expect(
          tester.widget<TextFormField>(field('description')).controller!.text,
          'Retained vehicle description');
      fail = noAck = wrongAck = false;
      await submit(tester);
      expect(writes.length, 2);
      expect(uploads.length, 1);
      expect(jsonDecode(writes.last.body)['id'], first['id']);
      expect(
          tester.widget<TextFormField>(field('description')).controller!.text,
          isEmpty);
      expect(find.text(t('ui_ad_submitted')), findsOneWidget);
      await finish(tester);
    });
  }
  testWidgets('backend schema rejection retains the draft without retry',
      (tester) async {
    missingPlateRegions = true;
    await mount(tester);
    await draft(tester);
    await submit(tester);
    expect(writes, hasLength(1));
    final request = jsonDecode(writes.single.body) as Map<String, dynamic>;
    expect(request.containsKey('plate_regions'), isTrue);
    expect(uploads, hasLength(1));
    expect(find.textContaining(t('ui_ad_publish_failed')), findsOneWidget);
    expect(find.textContaining('400'), findsOneWidget);
    expect(find.textContaining('schema cache'), findsNothing);
    await finish(tester);
  });
  testWidgets(
      'partial upload retries only the incomplete photo with a stable path',
      (tester) async {
    photos = [
      XFile.fromData(png, name: 'first.png'),
      XFile.fromData(png, name: 'second.png')
    ];
    failUploadAt = 2;
    await mount(tester);
    await draft(tester);
    await submit(tester);
    expect(writes, isEmpty);
    expect(uploads.length, 2);
    expect(find.text(t('ui_car_upload_failed')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    final path = uploads.last.url.queryParameters['path'];
    failUploadAt = 0;
    await submit(tester);
    expect(uploads.length, 3);
    expect(uploads.last.url.queryParameters['path'], path);
    expect(writes.length, 1);
    expect(
        jsonDecode(jsonDecode(writes.single.body)['image_url']), hasLength(2));
    await finish(tester);
  });
  testWidgets('pending upload freezes fields selectors photos and publishing',
      (tester) async {
    uploadGate = Completer<void>();
    await mount(tester);
    await draft(tester);
    await submit(tester);
    expect(uploads.length, 1);
    expect(writes, isEmpty);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    expect(
        find.byKey(const ValueKey('car_submission_progress')), findsOneWidget);
    await reveal(tester, field('brand'));
    expect(tester.widget<TextFormField>(field('brand')).enabled, isFalse);
    for (final label in ['field_province', 'car_type']) {
      final target = find.byKey(ValueKey('publish:${t(label)}:'));
      await reveal(tester, target);
      expect(tester.widget<DropdownButtonFormField<String>>(target).onChanged,
          isNull);
    }

    await tester.pumpWidget(const SizedBox());
    uploadGate!.complete();
    await frames(tester);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending insert freezes form and tolerates route disposal',
      (tester) async {
    gate = Completer<void>();
    await mount(tester);
    await draft(tester);
    await submit(tester);
    expect(writes.length, 1);
    await reveal(tester, field('model'));
    expect(tester.widget<TextFormField>(field('model')).enabled, isFalse);
    await tester.pumpWidget(const SizedBox());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'picker failure and cancellation preserve current draft without raw errors',
      (tester) async {
    pickerFails = true;
    await mount(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text(t('ui_pick_images_failed')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    pickerFails = false;
    photos = [];
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text(t('car_add_images')), findsOneWidget);
    expect(uploads, isEmpty);
    await finish(tester);
  });
  testWidgets(
      'picker pending prevents a second selection and survives disposal',
      (tester) async {
    pickerGate = Completer<void>();
    await mount(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(pickCalls, 1);
    await tester.pumpWidget(const SizedBox());
    pickerGate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('session loss after upload prevents publishing', (tester) async {
    uploadGate = Completer<void>();
    await mount(tester);
    await draft(tester);
    await submit(tester);
    await signOutAccount(tester);
    uploadGate!.complete();
    await frames(tester);
    expect(writes, isEmpty);
    expect(find.text(t('ui_car_session_changed')), findsOneWidget);
    await signInAccount(tester);
    await finish(tester);
  });
  testWidgets(
      'one unreadable selection does not leave photo and byte lists inconsistent',
      (tester) async {
    photos = [
      XFile.fromData(png, name: 'valid.png'),
      XFile('/tmp/motriiq-missing-photo-fixture.png')
    ];
    await mount(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text(t('ui_pick_images_failed')), findsOneWidget);
    expect(find.text(t('car_add_images')), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    photos = [XFile.fromData(png, name: 'retry.png')];
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text('1 / 1'), findsOneWidget);
    await finish(tester);
  });
  testWidgets(
      'selection cap and accessible photo removal keep preview consistent',
      (tester) async {
    photos = List.generate(16, (i) => XFile.fromData(png, name: '$i.png'));
    await mount(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text('1 / 15'), findsOneWidget);
    expect(find.text(t('img_only_15_added')), findsOneWidget);
    final remove = find.byTooltip(t('common_delete')).first;
    expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(remove);
    await frames(tester);
    expect(find.text('1 / 14'), findsOneWidget);
    expect(uploads, isEmpty);
    await finish(tester);
  });
  testWidgets('corrupt image bytes are rejected before preview or upload',
      (tester) async {
    photos = [
      XFile.fromData(Uint8List.fromList([1, 2, 3]), name: 'broken.jpg')
    ];
    await mount(tester);
    await tester.tap(find.text(t('car_add_images')));
    await frames(tester);
    expect(find.text(t('ui_pick_images_failed')), findsOneWidget);
    expect(find.text(t('car_add_images')), findsOneWidget);
    expect(uploads, isEmpty);
    await finish(tester);
  });
  testWidgets(
      'normal Add Car layout and consecutive successful listings use fresh draft ids',
      (tester) async {
    await mount(tester, scale: 1, width: 900);
    await draft(tester);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    scroll.position.jumpTo(0);
    await frames(tester);
    expect(tester.getSize(find.byType(ListView).first).width,
        lessThanOrEqualTo(760));
    await hold(tester, 'ADDCAR_REGULAR');
    await submit(tester);
    expect(writes.length, 1);
    expect(find.text(t('ui_ad_submitted')), findsOneWidget);
    final first = jsonDecode(writes.first.body)['id'];
    await draft(tester);
    await submit(tester);
    expect(writes.length, 2);
    expect(uploads.length, 2);
    expect(jsonDecode(writes.last.body)['id'], isNot(first));
    expect(uploads.first.url.queryParameters['path'],
        isNot(uploads.last.url.queryParameters['path']));
    await finish(tester);
  });
  testWidgets(
      'required and invalid fields show visible guidance without uploads',
      (tester) async {
    await mount(tester);
    await submit(tester);
    expect(find.text(t('ui_car_check_fields')), findsOneWidget);
    expect(uploads, isEmpty);
    expect(writes, isEmpty);
    await input(tester, 'brand', 'Toyota');
    await input(tester, 'model', 'Land Cruiser');
    await input(tester, 'year', '٢٢٠٠');
    await submit(tester);
    expect(find.text(t('ui_car_check_fields')), findsOneWidget);
    expect(uploads, isEmpty);
    expect(writes, isEmpty);
    await input(tester, 'year', '٢٠٢٤');
    await input(tester, 'price', 'NaN');
    await submit(tester);
    expect(uploads, isEmpty);
    expect(writes, isEmpty);
    expect(find.text(t('misc_publish_ad')).hitTestable(), findsOneWidget);
    await finish(tester);
  });
  testWidgets('phone is required for the legacy cars.phone column',
      (tester) async {
    await mount(tester);
    await draft(tester);
    await input(tester, 'phone', '');
    await submit(tester);
    expect(find.text(t('wanted')), findsOneWidget);
    expect(uploads, isEmpty);
    expect(writes, isEmpty);
    await finish(tester);
  });
}
