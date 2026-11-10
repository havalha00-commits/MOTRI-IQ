import 'dart:async';
import 'dart:convert';
import 'support/current_typography_checkpoint.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/market_images.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/ui/photo_gallery.dart';

const photo =
    'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg';
const uid = '00000000-0000-4000-8000-000000000001';
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

http.Response reply(http.Request req, Object? body, {int status = 200}) =>
    http.Response(jsonEncode(body), status,
        request: req,
        headers: {'content-type': 'application/json; charset=utf-8'});
void main() {
  var sampleBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg==');
  final writes = <http.Request>[];
  final uploads = <http.Request>[];
  var failUploadAt = 0;
  Completer<void>? gate;
  Completer<void>? adminGate;
  bool fail = false,
      noAck = false,
      admin = false,
      deleteFail = false,
      deleteNoAck = false;
  String? rpcErrorCode;
  late Map<String, dynamic> item;
  setUpAll(() async {
    if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      final image =
          await http.get(Uri.parse(photo)).timeout(const Duration(seconds: 25));
      expect(image.statusCode, 200);
      sampleBytes = image.bodyBytes;
    }

    SharedPreferences.setMockInitialValues({});
    final payload = base64Url
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
          if (req.url.path == '/auth/v1/token') {
            return reply(req, {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.$signature',
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
            });
          }
          if (req.url.path.endsWith('/app_admins')) {
            final allowed = admin;
            final pending = adminGate;
            if (pending != null) await pending.future;
            return reply(req, allowed ? {'user_id': uid} : null);
          }
          if (req.url.path.endsWith('/admin_delete_ad')) {
            writes.add(req);
            if (gate != null) await gate!.future;
            if (rpcErrorCode != null) {
              return reply(
                  req,
                  {
                    'code': rpcErrorCode,
                    'message': 'Could not find function public.admin_delete_ad'
                  },
                  status: 404);
            }
            return reply(req, {
              'ok': !fail,
              'deleted': noAck ? 0 : 1,
              'reason': 'private diagnostic'
            });
          }
          if (req.url.path.contains('/storage/v1/object/')) {
            uploads.add(req);
            return reply(
                req,
                failUploadAt == uploads.length
                    ? {'message': 'private upload detail'}
                    : {'Key': req.url.path.split('/object/').last},
                status: failUploadAt == uploads.length ? 400 : 200);
          }
          if (req.method == 'PATCH') {
            writes.add(req);
            if (gate != null) await gate!.future;
            if (fail) {
              return reply(
                  req, {'message': 'private database details', 'code': 'XX000'},
                  status: 500);
            }
            return reply(
                req,
                noAck
                    ? []
                    : [
                        {'id': 'item-1'}
                      ]);
          }
          return reply(req, []);
        }));
    backendApi = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => supabase.auth.currentSession?.accessToken,
      client: MockClient((req) async {
        if (req.url.path.endsWith('/uploads/object')) {
          uploads.add(req);
          if (failUploadAt == uploads.length) {
            return reply(req, {'error': 'Image upload failed'}, status: 502);
          }
          final bucket = req.url.queryParameters['bucket'];
          final path = req.url.queryParameters['path']!;
          return reply(req, {
            'success': true,
            'data': {
              'public_url':
                  'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/$bucket/$path'
            }
          });
        }
        if (req.url.path.contains('/market/') && req.method == 'DELETE') {
          writes.add(req);
          if (gate != null) await gate!.future;
          if (deleteFail) {
            return reply(
              req,
              {'error': 'Failed to delete listing'},
              status: 503,
            );
          }
          return reply(
            req,
            deleteNoAck
                ? {'success': true, 'data': {}}
                : {
                    'success': true,
                    'data': {'id': 'item-1'}
                  },
          );
        }
        if (req.url.path.contains('/market/') && req.method == 'PATCH') {
          writes.add(req);
          if (gate != null) await gate!.future;
          if (fail) {
            return reply(
              req,
              {'error': 'Failed to save listing images'},
              status: 503,
            );
          }
          return reply(
            req,
            noAck
                ? {'success': true, 'data': {}}
                : {
                    'success': true,
                    'data': {'id': 'item-1'}
                  },
          );
        }
        return reply(req, {'error': 'not found'}, status: 404);
      }),
    );
    await supabase.auth
        .signInWithPassword(email: 'fixture@example.com', password: 'fixture');
  });
  setUp(() async {
    if (supabase.auth.currentUser == null) {
      await supabase.auth.signInWithPassword(email: 'fixture@example.com', password: 'fixture');
    }
    adminGate = null;
    writes.clear();
    uploads.clear();
    failUploadAt = 0;
    gate = null;
    fail = noAck = admin = deleteFail = deleteNoAck = false;
    rpcErrorCode = null;
    appLocaleNotifier.value = AppLocale.en;
    AppColors.isDark = false;
    item = {
      'id': 'item-1',
      'user_id': uid,
      'title': 'Original alloy wheels — full set',
      'price': '١٬٢٥٠',
      'description':
          'Original parts with a clear condition description. Suitable for daily use.',
      'city': 'بغداد',
      'governorate': 'بغداد',
      'category': 'Wheels and automotive accessories',
      'phone': '+964 770 123 4567',
      'images': [photo, '$photo?second=1']
    };
  });
  Future<void> mount(WidgetTester tester,
      {Widget? page, double scale = 1}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(390, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }
    await tester.pumpWidget(MaterialApp(
        key: UniqueKey(),
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
        home: page ?? MarketItemDetailsPage(item: item)));
    await frames(tester);
  }

  Future<void> openEditor(WidgetTester tester,
      {Map<String, dynamic>? data, double scale = 1}) async {
    await mount(tester,
        scale: scale,
        page: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<List<String>>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            EditMarketImagesDialog(item: data ?? item)),
                    child: const Text('Open editor')))));
    await tester.tap(find.text('Open editor'));
    await frames(tester);
  }

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.6]) {
        testWidgets('Market detail ${locale.code} dark=$dark scale=$scale',
            (tester) async {
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          if (scale > 1) {
            item['category'] = List.filled(10, 'قطع غيار وإكسسوارات').join(' ');
          }
          await mount(tester, scale: scale);
          expect(find.text(formatUsd(1250)), findsOneWidget);
          final title = tester.widget<Text>(find.text(item['title']));
          expect(title.maxLines, isNull);
          expect(title.textDirection, TextDirection.ltr);
          if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
            Object? imageError;
            await tester.runAsync(() => precacheImage(const NetworkImage(photo),
                    tester.element(find.byType(MarketItemGallery)),
                    onError: (error, _) => imageError = error)
                .timeout(const Duration(seconds: 25)));
            await frames(tester);
            expect(imageError, isNull);
          }
          expect(tester.takeException(), isNull);
          if (const bool.fromEnvironment('UI_REVIEW_HOLD') &&
              (locale == AppLocale.ar && !dark ||
                  locale == AppLocale.ku && dark)) {
            debugPrint(
                'REFERENCE_MARKET_${locale.code.toUpperCase()}${scale > 1 ? '_LARGE' : ''}');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 15)));
          }
          if (scale > 1) {
            await currentTypographyCheckpoint(tester, 'MARKET_DETAIL_CURRENT');
          }
          await tester.scrollUntilVisible(find.text(item['description']), 280,
              scrollable: find
                  .descendant(
                      of: find.byType(ListView).first,
                      matching: find.byType(Scrollable))
                  .first);
          await frames(tester);
          expect(
              tester.widget<Text>(find.text(item['description'])).textDirection,
              TextDirection.ltr);
          if (scale > 1) {
            await currentTypographyCheckpoint(tester, 'MARKET_DETAIL_BODY');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
  testWidgets('Market empty photos and job salary have no invented currency',
      (tester) async {
    item.remove('price');
    item['salary'] = '1200000';
    item['images'] = [];
    await mount(tester, scale: 1.6);
    expect(find.text(t('market_no_images_ad')), findsOneWidget);
    expect(find.text('1200000'), findsOneWidget);
    expect(find.textContaining('USD'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Market gallery ${locale.code} dark=$dark current navigation',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester,
            scale: 1.6,
            page: const Scaffold(
                body:
                    SafeArea(child: MarketItemGallery(urls: [photo, photo]))));
        final gallery = find.byType(MarketItemGallery);
        final context = tester.element(gallery);
        if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          Object? failure;
          await tester.runAsync(() => precacheImage(
                  const NetworkImage(photo), context,
                  onError: (error, _) => failure = error)
              .timeout(const Duration(seconds: 25)));
          await frames(tester);
          expect(failure, isNull);
        }
        final labels = MaterialLocalizations.of(context);
        final next = find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == labels.nextPageTooltip);
        final previous = find.byWidgetPredicate(
            (w) => w is IconButton && w.tooltip == labels.previousPageTooltip);
        expect(tester.getSize(next).shortestSide, greaterThanOrEqualTo(48));
        expect(tester.getSize(previous).shortestSide, greaterThanOrEqualTo(48));
        expect((tester.widget<IconButton>(previous).icon as Icon).icon,
            Icons.chevron_left);
        expect((tester.widget<IconButton>(next).icon as Icon).icon,
            Icons.chevron_right);
        final before = tester.getCenter(previous).dx;
        final after = tester.getCenter(next).dx;
        expect(before > after, locale.direction == TextDirection.rtl,
            reason:
                'Previous stays at logical start; Flutter mirrors its glyph once');
        expect(tester.widget<IconButton>(previous).onPressed, isNull);
        await tester.tap(next);
        await frames(tester);
        expect(find.text('2 / 2'), findsOneWidget);
        expect(tester.widget<IconButton>(next).onPressed, isNull);
        await currentTypographyCheckpoint(tester, 'MARKET_GALLERY_CURRENT');
        await tester.tap(find
            .descendant(of: gallery, matching: find.byType(CarPhoto))
            .first);
        await frames(tester);
        final fullscreen = find.byType(PhotoGallery);
        expect(fullscreen, findsOneWidget);
        expect(find.descendant(of: fullscreen, matching: find.text('2 / 2')),
            findsOneWidget);
        await currentTypographyCheckpoint(tester, 'MARKET_GALLERY_FULLSCREEN');
        await tester.tap(find.descendant(
            of: fullscreen, matching: find.byType(CloseButton)));
        await frames(tester);
        expect(fullscreen, findsNothing);
        await tester.tap(previous);
        await frames(tester);
        expect(find.text('1 / 2'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
      });
    }
  }
  testWidgets('gallery arrows mirror, stop at ends, and use shared zoom viewer',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    await mount(tester);
    final context = tester.element(find.byType(MarketItemGallery));
    final labels = MaterialLocalizations.of(context);
    final previous = find.widgetWithIcon(IconButton, Icons.chevron_left);
    final next = find.widgetWithIcon(IconButton, Icons.chevron_right);
    expect(tester.widget<IconButton>(previous).onPressed, isNull);
    expect(tester.widget<IconButton>(next).tooltip, labels.nextPageTooltip);
    expect(tester.getSize(next).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(next);
    await frames(tester);
    expect(find.text('2 / 2'), findsOneWidget);
    expect(tester.widget<IconButton>(next).onPressed, isNull);
    await tester.tap(find.byType(CarPhoto).first);
    await frames(tester);
    expect(find.byType(PhotoGallery), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'image editor validates count and freezes pending acknowledged save',
      (tester) async {
    item['images'] = [photo];
    await openEditor(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(find.text(t('ui_market_photo_limit')), findsWidgets);
    expect(writes, isEmpty);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    item['images'] = [for (var i = 0; i < 5; i++) '$photo?image=$i'];
    gate = Completer<void>();
    await tester.tap(find.text('Open editor'));
    await frames(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(writes, hasLength(1));
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(
        tester
            .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
            .enabled,
        isFalse);
    final pop = tester.widget<PopScope>(find
        .descendant(
            of: find.byType(EditMarketImagesDialog),
            matching: find.byType(PopScope))
        .first);
    expect(pop.canPop, isFalse);
    expect(writes.single.url.path, endsWith('/market/items/item-1/images'));
    expect(jsonDecode(writes.single.body)['images'], hasLength(5));
    gate!.complete();
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('image save no-ack and failure retain editor with generic retry',
      (tester) async {
    item['images'] = [for (var i = 0; i < 5; i++) '$photo?image=$i'];
    noAck = true;
    await openEditor(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(find.text(t('market_images_error')), findsOneWidget);
    noAck = false;
    fail = true;
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsOneWidget);
    expect(find.textContaining('private database'), findsNothing);
    fail = false;
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
  });
  testWidgets('job editor saves to jobs without requiring five photos',
      (tester) async {
    item['salary'] = 100;
    item['images'] = [];
    await openEditor(tester);
    expect(find.byType(JobImagesPicker), findsOneWidget);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(writes.single.url.path, endsWith('/market/jobs/item-1/images'));
    expect(jsonDecode(writes.single.body)['images'], isEmpty);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
  });
  testWidgets(
      'other owner cannot write and pending completion tolerates disposal',
      (tester) async {
    item['user_id'] = 'someone-else';
    await openEditor(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(writes, isEmpty);
    expect(find.text(t('market_login_to_save')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
    item['user_id'] = uid;
    item['images'] = [for (var i = 0; i < 5; i++) '$photo?image=$i'];
    gate = Completer<void>();
    await openEditor(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    gate!.complete();
    await frames(tester);
    expect(tester.takeException(), isNull);
  });
  testWidgets('market image route expires after same-user session replacement',
      (tester) async {
    await mount(tester);
    final edit = find.widgetWithText(FilledButton, t('market_edit_images_2'));
    await tester.scrollUntilVisible(edit, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(edit);
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsOneWidget);
    await tester.runAsync(() => supabase.auth.signOut());
    await frames(tester);
    expect(find.byKey(const ValueKey('account_scoped_view_expired')), findsOneWidget);
    await tester.runAsync(() => supabase.auth.signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
    expect(find.byKey(const ValueKey('account_scoped_view_expired')), findsOneWidget);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('market stale admin lookup cannot survive same-user return',
      (tester) async {
    admin = true;
    adminGate = Completer<void>();
    final pending = adminGate!;
    await mount(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    await tester.runAsync(() => supabase.auth.signOut());
    await frames(tester);
    admin = false;
    adminGate = null;
    await tester.runAsync(() => supabase.auth.signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
    await frames(tester);
    pending.complete();
    await frames(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('market late delete cannot pop a replacement same-user session',
      (tester) async {
    admin = true;
    await mount(tester);
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    gate = Completer<void>();
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(writes, hasLength(1));
    await tester.runAsync(() => supabase.auth.signOut());
    await frames(tester);
    expect(find.byTooltip(t('admin_delete_ad')), findsNothing);
    await tester.runAsync(() => supabase.auth.signInWithPassword(email: 'fixture@example.com', password: 'fixture'));
    await frames(tester);
    gate!.complete();
    await frames(tester);
    expect(find.byType(MarketItemDetailsPage), findsOneWidget);
    expect(find.text(t('admin_delete_ad_done')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'admin deletion confirms, guards requests and requires one deleted row',
      (tester) async {
    admin = true;
    noAck = true;
    await mount(tester,
        page: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketItemDetailsPage(item: item))),
                    child: const Text('Open listing')))));
    await tester.tap(find.text('Open listing'));
    await frames(tester);
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(writes, isEmpty);
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    gate = Completer<void>();
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(writes, hasLength(1));
    expect(
        tester
            .widget<IconButton>(find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == t('admin_delete_ad')))
            .onPressed,
        isNull);
    gate!.complete();
    await frames(tester);
    expect(find.byType(MarketItemDetailsPage), findsOneWidget);
    expect(find.text(t('admin_delete_ad_failed')), findsOneWidget);
    expect(find.text(t('admin_delete_ad_db_error')), findsOneWidget);
    expect(find.textContaining('private diagnostic'), findsNothing);
    gate = null;
    noAck = false;
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(find.byType(MarketItemDetailsPage), findsNothing);
    expect(jsonDecode(writes.last.body)['p_table'], 'market_items');
    expect(tester.takeException(), isNull);
  });
  testWidgets('admin delete explains when the existing RPC is missing',
      (tester) async {
    admin = true;
    rpcErrorCode = 'PGRST202';
    await mount(tester,
        page: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketItemDetailsPage(item: item))),
                    child: const Text('Open listing')))));
    await tester.tap(find.text('Open listing'));
    await frames(tester);
    await tester.tap(find.byTooltip(t('admin_delete_ad')));
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(
        find.text(t('admin_delete_ad_setup_required')), findsOneWidget);
    expect(find.textContaining('Could not find function'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('photo editor wraps Kurdish text in dark mode at enlarged size',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ku;
    AppColors.isDark = true;
    await openEditor(tester, scale: 1.6);
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('UI_REVIEW_HOLD')) {
      debugPrint('REFERENCE_MARKET_EDITOR');
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
    }
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
  });
  testWidgets(
      'market owner can delete only their listing after confirmation',
      (tester) async {
    await mount(tester,
        page: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketItemDetailsPage(item: item))),
                    child: const Text('Open listing')))));
    await tester.tap(find.text('Open listing'));
    await frames(tester);
    final delete = find.text(t('market_delete_ad'));
    await tester.scrollUntilVisible(delete, 280,
        scrollable: find.descendant(
            of: find.byType(MarketItemDetailsPage),
            matching: find.byType(Scrollable)).first);
    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(writes.where((request) => request.method == 'DELETE'), isEmpty);

    await tester.scrollUntilVisible(delete, 280,
        scrollable: find.descendant(
            of: find.byType(MarketItemDetailsPage),
            matching: find.byType(Scrollable)).first);
    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    final request =
        writes.singleWhere((request) => request.method == 'DELETE');
    expect(request.url.path, endsWith('/market/items/item-1'));
    expect(find.byType(MarketItemDetailsPage), findsNothing);
    expect(find.text(t('market_delete_ad_done')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('market owner delete reports permission errors and keeps ad',
      (tester) async {
    deleteFail = true;
    await mount(tester,
        page: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => MarketItemDetailsPage(item: item))),
                    child: const Text('Open listing')))));
    await tester.tap(find.text('Open listing'));
    await frames(tester);
    final delete = find.text(t('market_delete_ad'));
    await tester.scrollUntilVisible(delete, 280,
        scrollable: find.descendant(
            of: find.byType(MarketItemDetailsPage),
            matching: find.byType(Scrollable)).first);
    await tester.tap(delete);
    await frames(tester);
    await tester.tap(find.text(t('common_delete')));
    await frames(tester);
    expect(find.byType(MarketItemDetailsPage), findsOneWidget);
    expect(find.text(t('market_delete_ad_failed')), findsOneWidget);
    expect(find.textContaining('42501'), findsNothing);
    expect(find.textContaining('private delete details'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('other users cannot see the market owner delete action',
      (tester) async {
    item['user_id'] = '00000000-0000-4000-8000-000000000002';
    await mount(tester);
    expect(find.text(t('market_delete_ad')), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'owner image save refreshes the open detail without mutating input',
      (tester) async {
    item['images'] = [for (var i = 0; i < 5; i++) '$photo?image=$i'];
    await mount(tester);
    final edit = find.widgetWithText(FilledButton, t('market_edit_images_2'));
    await tester.scrollUntilVisible(edit, 280,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(edit);
    await frames(tester);
    final second = find.descendant(
        of: find.byType(EditMarketImagesDialog),
        matching: find.byWidgetPredicate((w) =>
            w is Image &&
            w.image is NetworkImage &&
            (w.image as NetworkImage).url == '$photo?image=1'));
    await tester.tap(second);
    await frames(tester);
    await tester.tap(find.text(t('common_save')));
    await frames(tester);
    expect(find.byType(EditMarketImagesDialog), findsNothing);
    expect(find.byType(MarketItemDetailsPage), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1000));
    await frames(tester);
    expect(
        tester
            .widget<MarketItemGallery>(find.byType(MarketItemGallery))
            .urls
            .first,
        '$photo?image=1');
    expect((item['images'] as List).first, '$photo?image=0');
    expect(tester.takeException(), isNull);
  });
  testWidgets('local job photo previews bytes and remove remains a 44px target',
      (tester) async {
    final entries = [
      MarketImageEntry.file(XFile.fromData(
          base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),
          name: 'fixture.png'))
    ];
    await mount(tester,
        page: Scaffold(
            body: SingleChildScrollView(
                child: JobImagesPicker(images: entries))));
    await frames(tester);
    expect(tester.widget<Image>(find.byType(Image).first).image,
        isA<MemoryImage>());
    final remove = find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == t('car_delete_image'));
    expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(remove);
    await frames(tester);
    expect(entries, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
      'image parser keeps valid HTTP links, removes duplicates and rejects junk',
      () {
    expect(
        marketItemImageUrls({
          'images':
              '["https://x.test/a","null","file:///tmp/a","https://x.test/a"]'
        }),
        ['https://x.test/a']);
  });
  for (final jobs in [false, true]) {
    for (final locale in AppLocale.values) {
      testWidgets(
          'image editor partial upload and database retry jobs=$jobs ${locale.code}',
          (tester) async {
        if (jobs) item['salary'] = 100;
        item['images'] =
            jobs ? <String>[] : [for (var i = 0; i < 4; i++) '$photo?image=$i'];
        appLocaleNotifier.value = locale;
        AppColors.isDark = locale == AppLocale.ku;
        await openEditor(tester, scale: 1.4);
        final photos = jobs
            ? tester
                .widget<JobImagesPicker>(find.byType(JobImagesPicker))
                .images
            : tester
                .widget<MarketImagesPicker>(find.byType(MarketImagesPicker))
                .images;
        photos.addAll(List.generate(
            2,
            (i) => MarketImageEntry.file(XFile.fromData(sampleBytes,
                name: const bool.fromEnvironment('NATIVE_VIEWPORT')
                    ? '$i.jpg'
                    : '$i.png'))));
        failUploadAt = 2;
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(uploads.length, 2);
        expect(writes, isEmpty);
        expect(find.text(t('ui_car_upload_failed')), findsOneWidget);
        await currentTypographyCheckpoint(
            tester, 'MEDIA_EDIT_${jobs ? 'JOB' : 'MARKET'}');
        failUploadAt = 0;
        fail = true;
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(uploads.length, 3);
        expect(uploads.last.url.queryParameters['path'],
            uploads[1].url.queryParameters['path']);
        expect(writes.length, 1);
        fail = false;
        await tester.tap(find.text(t('common_save')));
        await frames(tester);
        expect(uploads.length, 3);
        expect(writes.length, 2);
        expect(jsonDecode(writes.first.body)['images'],
            jsonDecode(writes.last.body)['images']);
        expect(find.byType(EditMarketImagesDialog), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
