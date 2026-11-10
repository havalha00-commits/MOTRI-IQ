import 'dart:async';
import 'dart:convert';
import 'support/current_typography_checkpoint.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/market_images.dart';
import 'package:motri_iq/ui/generic_ad_editor_dialog.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/search/job_types.dart';

const uid = '00000000-0000-4000-8000-000000000001';
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

http.Response reply(http.Request request, Object? body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      request: request,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  final writes = <http.Request>[];
  final uploads = <http.Request>[];
  var failUploadAt = 0;
  Completer<void>? uploadGate;
  Completer<void>? gate;
  var noAck = false, fail = false;
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
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
          } else if (req.url.path.contains('/storage/v1/object/')) {
            uploads.add(req);
            await uploadGate?.future;
            status = failUploadAt == uploads.length ? 400 : 200;
            body = status == 400
                ? {'message': 'private upload detail'}
                : {'Key': req.url.path.split('/object/').last};
          } else if (req.method == 'POST') {
            writes.add(req);
            if (gate != null) await gate!.future;
            if (fail) {
              status = 500;
              body = {'message': 'private database detail', 'code': 'XX000'};
            } else {
              body = noAck
                  ? []
                  : [
                      {'id': jsonDecode(req.body)['id']}
                    ];
            }
          }
          return http.Response(jsonEncode(body), status,
              request: req,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => supabase.auth.currentSession?.accessToken,
      client: MockClient((req) async {
        if (req.url.path.endsWith('/ugc/acceptance')) {
          return reply(req, {
            'success': true,
            'data': {'accepted': true, 'policy_version': '2026-11-05'}
          });
        }
        if (req.url.path.endsWith('/uploads/object')) {
          uploads.add(req);
          await uploadGate?.future;
          if (failUploadAt == uploads.length) {
            return reply(req, {'error': 'Image upload failed'}, status: 502);
          }
          final bucket = req.url.queryParameters['bucket'];
          final path = req.url.queryParameters['path']!;
          return reply(req, {
            'success': true,
            'data': {
              'public_url':
                  'https://example.supabase.co/storage/v1/object/public/$bucket/$path'
            }
          });
        }
        if (req.url.path.endsWith('/market/items') ||
            req.url.path.endsWith('/market/jobs')) {
          writes.add(req);
          if (gate != null) await gate!.future;
          if (fail) {
            return reply(
              req,
              {'error': 'Failed to publish listing'},
              status: 503,
            );
          }
          return reply(
            req,
            noAck
                ? {'success': true, 'data': {}}
                : {
                    'success': true,
                    'data': {'id': jsonDecode(req.body)['id']}
                  },
          );
        }
        return reply(req, {'error': 'not found'}, status: 404);
      }),
    );
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() {
    writes.clear();
    uploads.clear();
    failUploadAt = 0;
    uploadGate = null;
    gate = null;
    noAck = fail = false;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
  });
  Future<void> mount(WidgetTester tester,
      {bool market = true, double scale = 1}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    final appKey = UniqueKey();
    await tester.pumpWidget(ValueListenableBuilder<AppLocale>(
        valueListenable: appLocaleNotifier,
        builder: (context, locale, _) => AppStringsScope(
            locale: locale,
            child: MaterialApp(
                key: appKey,
                debugShowCheckedModeBanner: false,
                theme: buildAppTheme(
                    AppColors.isDark ? Brightness.dark : Brightness.light),
                locale: appLocale.locale,
                supportedLocales: const [
                  Locale('ar'),
                  Locale('ku'),
                  Locale('en')
                ],
                localizationsDelegates: appLocalizationsDelegates,
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!),
                home: Scaffold(
                    body: SafeArea(
                        child: Builder(
                            builder: (context) => TextButton(
                                onPressed: () => showDialog<bool>(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (_) => GenericAdEditorDialog(
                                        isMarket: market)),
                                child: const Text('Create listing')))))))));
    await frames(tester);
    await tester.tap(find.text('Create listing'));
    await frames(tester);
  }

  Future<void> fill(WidgetTester tester, {bool market = true}) async {
    await tester.enterText(find.byKey(const ValueKey('generic_title')),
        'Original automotive listing');
    await tester.enterText(
        find.byKey(const ValueKey('generic_price')), '١٬٢٥٠٫٥');
    if (market) {
      tester
          .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
          .images
          .addAll([
        for (var i = 0; i < 2; i++)
          MarketImageEntry.url('https://example.com/$i.png')
      ]);
    } else {
      await tester.enterText(
          find.byKey(const ValueKey('generic_city')), 'بغداد');
      await tester.tap(find.byKey(const ValueKey('generic_shift')));
      await frames(tester);
      await tester.tap(find.text(t('job_shift_full')).last);
      await frames(tester);
    }
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final market in [false, true]) {
        testWidgets(
            'Generic draft ${locale.code} dark=$dark market=$market direction',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          await mount(tester, market: market);
          final title = find.byKey(const ValueKey('generic_title'));
          final controller = tester.widget<TextField>(title).controller!;
          const latin = TextEditingValue(
              text: 'Automotive listing',
              selection: TextSelection(baseOffset: 1, extentOffset: 5),
              composing: TextRange(start: 0, end: 6));
          controller.value = latin;
          await frames(tester);
          expect(
              tester.widget<TextField>(title).textDirection, TextDirection.ltr);
          expect(controller.value, latin);
          controller.text = 'إعلان سيارات';
          await frames(tester);
          expect(
              tester.widget<TextField>(title).textDirection, TextDirection.rtl);
          if (!market) {
            final city = find.byKey(const ValueKey('generic_city'));
            await tester.ensureVisible(city);
            await tester.enterText(city, 'Baghdad');
            await frames(tester);
            expect(tester.widget<TextField>(city).textDirection,
                TextDirection.ltr);
          }
          expect(
              tester
                  .widget<TextField>(
                      find.byKey(const ValueKey('generic_price')))
                  .textDirection,
              TextDirection.ltr);
          FocusManager.instance.primaryFocus?.unfocus();
          await frames(tester);
          await Scrollable.ensureVisible(tester.element(title));
          await frames(tester);
          await currentTypographyCheckpoint(
              tester, market ? 'GENERIC_MARKET_DRAFT' : 'GENERIC_JOB_DRAFT');
          await tester.tap(find.text(t('common_cancel')));
          await frames(tester);
          expect(find.byType(GenericAdEditorDialog), findsNothing);
          expect(writes, isEmpty);
          expect(tester.takeException(), isNull);
        });
        for (final scale in [1.0, 1.6]) {
          testWidgets(
              'create ${market ? 'market' : 'job'} ${locale.code} dark=$dark scale=$scale',
              (tester) async {
            appLocaleNotifier.value = locale;
            AppColors.isDark = dark;
            await mount(tester, market: market, scale: scale);
            expect(tester.takeException(), isNull);
            if (scale > 1 &&
                const bool.fromEnvironment('UI_REVIEW_HOLD') &&
                (locale == AppLocale.ar && !dark ||
                    locale == AppLocale.ku && dark)) {
              debugPrint(
                  'REFERENCE_CREATE_${market ? 'MARKET' : 'JOB'}_${locale.code.toUpperCase()}');
              await tester.runAsync(
                  () => Future<void>.delayed(const Duration(seconds: 15)));
            }
            await tester.tap(find.text(t('common_cancel')));
            await frames(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
  testWidgets(
      'validates localized numeric input and image minimum before publishing',
      (tester) async {
    await mount(tester);
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(find.text(t('field_write_product_name')), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('generic_title')), 'Listing');
    for (final invalid in ['-١', 'NaN', 'Infinity', '1e999', 'abc']) {
      await tester.enterText(
          find.byKey(const ValueKey('generic_price')), invalid);
      await tester.tap(find.text(t('account_publish')));
      await frames(tester);
      expect(find.text(t('ui_invalid_price')), findsOneWidget);
    }
    await tester.enterText(find.byKey(const ValueKey('generic_price')), '١٢٥٠');
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(find.text(t('ui_market_photo_limit')), findsWidgets);
    expect(writes, isEmpty);
  });
  testWidgets(
      'publishing freezes inputs and requires an acknowledged same draft ID',
      (tester) async {
    await mount(tester);
    await fill(tester);
    gate = Completer<void>();
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(writes, hasLength(1));
    final body = jsonDecode(writes.single.body);
    expect(body['price'], 1250.5);
    expect(body['user_id'], uid);
    expect(body['images'], hasLength(2));
    expect(
        body['id'],
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('generic_title')))
            .enabled,
        isFalse);
    expect(
        tester
            .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
            .enabled,
        isFalse);
    gate!.complete();
    await frames(tester);
    expect(find.byType(GenericAdEditorDialog), findsNothing);
  });
  testWidgets('no-ack and server failure retain draft and reuse ID on retry',
      (tester) async {
    await mount(tester);
    await fill(tester);
    noAck = true;
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(find.text(t('ui_ad_publish_failed')), findsOneWidget);
    final id = jsonDecode(writes.single.body)['id'];
    noAck = false;
    fail = true;
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(jsonDecode(writes.last.body)['id'], id);
    expect(find.textContaining('private database'), findsNothing);
    expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('generic_title')))
            .controller!
            .text,
        'Original automotive listing');
    fail = false;
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(find.byType(GenericAdEditorDialog), findsNothing);
  });
  testWidgets('job shift survives locale switch and persists canonical value',
      (tester) async {
    await mount(tester, market: false);
    await fill(tester, market: false);
    appLocaleNotifier.value = AppLocale.ku;
    await frames(tester);
    expect(find.text(t('job_shift_full')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(writes.single.url.path, endsWith('/market/jobs'));
    final body = jsonDecode(writes.single.body);
    expect(body['salary'], 1250.5);
    expect(body['job_type'], JobTypes.stored('job_shift_full'));
    expect(body.containsKey('price'), isFalse);
  });
  testWidgets('pending submit tolerates removal and guest cannot publish',
      (tester) async {
    await mount(tester);
    await fill(tester);
    gate = Completer<void>();
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester
        .runAsync(() => supabase.auth.signOut());
    await mount(tester);
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(find.text(t('misc_login_first_publish')), findsOneWidget);
    expect(writes, hasLength(1));
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  for (final market in [true, false]) {
    for (final locale in AppLocale.values) {
      testWidgets(
          'media partial upload and database retry market=$market ${locale.code}',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = locale == AppLocale.ku;
        await mount(tester, market: market, scale: 1.4);
        await fill(tester, market: market);
        final photos = market
            ? tester
                .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
                .images
            : tester
                .widget<JobImagesPicker>(find.byType(JobImagesPicker))
                .images;
        final bytes = base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
        final first =
            MarketImageEntry.file(XFile.fromData(bytes, name: 'first.png'));
        final second =
            MarketImageEntry.file(XFile.fromData(bytes, name: 'second.png'));
        photos.addAll([first, second]);
        failUploadAt = 2;
        await tester.tap(find.text(t('account_publish')));
        await frames(tester);
        expect(uploads.length, 2);
        expect(writes, isEmpty);
        expect(find.text(t('ui_car_upload_failed')), findsOneWidget);
        await currentTypographyCheckpoint(
            tester, 'MEDIA_CREATE_${market ? 'MARKET' : 'JOB'}');
        failUploadAt = 0;
        fail = true;
        await tester.tap(find.text(t('account_publish')));
        await frames(tester);
        expect(uploads.length, 3);
        expect(uploads[2].url.queryParameters['path'],
            uploads[1].url.queryParameters['path']);
        expect(uploads[0].url.queryParameters['path'],
            isNot(uploads[1].url.queryParameters['path']));
        expect(uploads[0].headers['content-type'], 'image/png');
        expect(writes.length, 1);
        final originalUrls =
            List<String>.from(jsonDecode(writes.single.body)['images']);
        // Reordering after a database error reuses completed files in new order.
        photos.remove(first);
        photos.add(first);
        fail = false;
        await tester.tap(find.text(t('account_publish')));
        await frames(tester);
        expect(uploads.length, 3);
        expect(writes.length, 2);
        final urls = List<String>.from(jsonDecode(writes.last.body)['images']);
        expect(urls.last, originalUrls[originalUrls.length - 2]);
        expect(jsonDecode(writes.first.body)['id'],
            jsonDecode(writes.last.body)['id']);
        expect(find.byType(GenericAdEditorDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
    testWidgets('media disposal stops remaining uploads market=$market',
        (tester) async {
      await mount(tester, market: market);
      await fill(tester, market: market);
      final photos = market
          ? tester
              .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
              .images
          : tester.widget<JobImagesPicker>(find.byType(JobImagesPicker)).images;
      photos.addAll(List.generate(
          2,
          (i) => MarketImageEntry.file(XFile.fromData(
              base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),
              name: '$i.png'))));
      uploadGate = Completer<void>();
      await tester.tap(find.text(t('account_publish')));
      await frames(tester);
      expect(uploads.length, 1);
      await tester.pumpWidget(const SizedBox());
      uploadGate!.complete();
      await frames(tester);
      expect(uploads.length, 1);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'account loss during photo upload stops later photos and database writes',
      (tester) async {
    await mount(tester);
    await fill(tester);
    final photos = tester
        .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
        .images;
    photos.addAll(List.generate(
        2,
        (i) => MarketImageEntry.file(XFile.fromData(
            base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),
            name: '$i.png'))));
    uploadGate = Completer<void>();
    await tester.tap(find.text(t('account_publish')));
    await frames(tester);
    expect(uploads.length, 1);
    await tester
        .runAsync(() => supabase.auth.signOut());
    uploadGate!.complete();
    await frames(tester);
    expect(uploads.length, 1);
    expect(writes, isEmpty);
    expect(find.text(t('ui_business_session_changed')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
    expect(tester.takeException(), isNull);
  });
}
