import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/search/business_categories.dart';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'support/business_submission_fixture.dart';

class _MemStorage extends FlutterSecureStorage {
  _MemStorage();
  final Map<String, String> m = {};
  @override
  Future<void> write({required String key, String? value, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions, AppleOptions? iOptions2, AppleOptions? webOptions2, WindowsOptions? wOptions2}) async {
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
  }
  @override
  Future<String?> read({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions, AppleOptions? iOptions2, AppleOptions? webOptions2, WindowsOptions? wOptions2}) async => m[key];
  @override
  Future<void> delete({required String key, AppleOptions? iOptions, AndroidOptions? aOptions, LinuxOptions? lOptions, AppleOptions? mOptions, WebOptions? webOptions, WindowsOptions? wOptions, AppleOptions? iOptions2, AppleOptions? webOptions2, WindowsOptions? wOptions2}) async {
    m.remove(key);
  }
}

Future<BackendAuthSession> _createAuthSession() async {
  final storage = _MemStorage();
  final session = BackendAuthSession(
    baseUrl: 'https://backend.example.test',
    storage: storage,
    client: MockClient((req) async {
      final path = req.url.path;
      if (path.endsWith('/api/auth/login') || path.endsWith('/auth/login')) {
        return http.Response(jsonEncode({
          'authenticated': true,
          'access_token': 'test-access-token',
          'refresh_token': 'test-refresh-token',
          'expires_in': 3600,
          'user': {'id': businessOwner, 'email': 'fixture@example.com', 'is_admin': false}
        }), 200);
      }
      if (path.endsWith('/api/auth/refresh') || path.endsWith('/auth/refresh')) {
        return http.Response(jsonEncode({
          'authenticated': true,
          'access_token': 'test-access-token-2',
          'refresh_token': 'test-refresh-token-2',
          'expires_in': 3600,
          'user': {'id': businessOwner, 'email': 'fixture@example.com', 'is_admin': false}
        }), 200);
      }
      if (path.endsWith('/api/auth/logout') || path.endsWith('/auth/logout')) {
        return http.Response('{}', 200);
      }
      if (path.endsWith('/api/profile/me') || path.endsWith('/profile/me')) {
        return http.Response(jsonEncode({'data': {'id': businessOwner, 'email': 'fixture@example.com'}}), 200);
      }
      return http.Response('{}', 404);
    }),
  );
  await session.login(email: 'fixture@example.com', password: 'fixture');
  if (session.user == null) {
    throw StateError('Failed to authenticate test session');
  }
  return session;
}

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2)));
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  final f = BusinessFixture();
  final logoBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAABJklEQVR4nO3ZzyqEcRSH8ef9WitZiNJolAXFwkpqothJlm6DG3ADbOxtXAaRv9lrWNjMsDQWEgu9NUM2bsA001M+u7M5/b6n09n8it3BKcyCXJALckEuyAW5IBfkglyQC3JBLsgFuSAX5IJckAtyQS7IBbkgF+SCXLrVaKtVXz/c/y3XDva2WnVEAdplOTw1WQwM/BRFMVSttMsS1wo9396Pzs8CI3PTL3cP9ES62Ovx9Kq6WgOqK7Xm6RXCANcTy4tAZWnh6ewGXYDP17evTmdwfAwo3z8wntHmyWVtZ7tn46frARpH5zObG43jC3ql+P+h6bMgF+SCXJALckEuyAW5IBfkglyQC3JBLsgFuSAX5IJckAtyQS7IBbkgF+SCXPr9gL/6BirINj9WA/2XAAAAAElFTkSuQmCC');
  var photoBytes = logoBytes;
  var pickerFails = false, corrupt = false, photoCount = 2, logoCalls = 0;
  Completer<void>? pickerGate;
  setUpAll(() async {
    if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      final response = await http
          .get(Uri.parse(
              'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg'))
          .timeout(const Duration(seconds: 25));
      expect(response.statusCode, 200);
      expect(response.bodyBytes.length, greaterThan(1000));
      photoBytes = response.bodyBytes;
    }
    await f.initialize();
  });
  setUp(() async {
    f.reset();
    backendApi = f.api;
    // Assign authenticated session before any widget usage - without reading global late first
    backendAuthSession = await _createAuthSession();
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][setUp] test=all session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][setUp] test=all err=$e');
    }
    pickerFails = corrupt = false;
    photoCount = 2;
    logoCalls = 0;
    pickerGate = null;
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  Future<XFile?> logoPicker() async {
    logoCalls++;
    await pickerGate?.future;
    if (pickerFails) throw StateError('private picker diagnostic');
    return XFile.fromData(corrupt ? Uint8List.fromList([1, 2, 3]) : logoBytes,
        name: 'logo.png');
  }

  Future<List<XFile>> imagePicker() async {
    await pickerGate?.future;
    if (pickerFails) throw StateError('private picker diagnostic');
    return List.generate(
        photoCount,
        (i) => XFile.fromData(photoBytes,
            name:
                'photo_$i.${const bool.fromEnvironment('NATIVE_VIEWPORT') ? 'jpg' : 'png'}'));
  }

  Future<void> mount(WidgetTester tester,
      {double scale = 1.6, double width = 360}) async {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = Size(width, 780);
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
            home: CreateBusinessAdPage(
                logoPicker: logoPicker, imagePicker: imagePicker))));
    await frames(tester);
  }

  Finder field(String name) => find.byKey(ValueKey('business_$name'));
  Future<void> reveal(WidgetTester tester, Finder target) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await frames(tester);
    final scroll = find.byType(Scrollable).first;
    tester.state<ScrollableState>(scroll).position.jumpTo(0);
    await frames(tester);
    await tester.scrollUntilVisible(target, 240,
        scrollable: scroll, maxScrolls: 80);
    await frames(tester);
  }

  Future<void> input(WidgetTester tester, String name, String text) async {
    await reveal(tester, field(name));
    await tester.tap(field(name));
    await frames(tester);
    await tester.enterText(field(name), text);
    await frames(tester);
    expect(tester.widget<TextFormField>(field(name)).controller!.text, text);
  }

  Future<void> fill(WidgetTester tester) async {
    await input(
        tester,
        'name',
        appLocale == AppLocale.ar
            ? 'مركز موتري لخدمة السيارات'
            : appLocale == AppLocale.ku
                ? 'ناوەندی خزمەتگوزاری مۆتری'
                : 'MOTRI Automotive Service Centre');
    final category = find.byKey(const ValueKey('business-category:'));
    await reveal(tester, category);
    await tester.tap(category);
    await frames(tester);
    await tester.tap(
        find.text(BusinessCategories.label(businessAdCategories.first)).last);
    await frames(tester);
    await input(tester, 'phone', '07701234567');
    await reveal(tester, field('logo_picker'));
    await tester.tap(field('logo_picker'));
    await frames(tester);
    await reveal(tester, field('images_picker'));
    await tester.tap(field('images_picker'));
    await frames(tester);
    await reveal(tester, find.byType(RadioListTile<String>));
    await tester.tap(find.byType(RadioListTile<String>));
    await frames(tester);
  }

  Future<void> review(WidgetTester tester) async {
    await reveal(tester, find.text(t('confirm_review')));
    await tester.tap(find.text(t('confirm_review')));
    await frames(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
  }

  Future<void> send(WidgetTester tester) async {
    await review(tester);
    await tester.tap(find.text(t('common_send')));
    await frames(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await frames(tester);
    expect(tester.takeException(), isNull);
  }

  Future<void> hold(WidgetTester tester, String marker) async {
    if (!const bool.fromEnvironment('UI_BUSINESS_SUBMISSION_HOLD')) return;
    debugPrint(marker);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 15)));
  }

  testWidgets('state gap business delayed packages', (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    f.packageGate = Completer<void>();
    await mount(tester);
    await reveal(tester, find.text(t('ui_loading_title')));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(t('pkg_none_available')), findsNothing);
    await currentTypographyCheckpoint(tester, 'GAP_BUSINESS_LOADING');
    f.packageGate!.complete();
    await frames(tester);
    await reveal(tester, find.byType(RadioGroup<String>));
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(RadioGroup<String>), findsOneWidget);
    expect(f.requests, isEmpty);
    expect(tester.takeException(), isNull);
    await finish(tester);
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'Business package placement direction ${locale.code} dark=$dark',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester,
            width: 320,
            scale: const bool.fromEnvironment('UI_BUSINESS_REGULAR') ? 1 : 1.6);
        await currentTypographyCheckpoint(tester, 'BUSINESS_REDESIGN_FORM');
        if (locale == AppLocale.ar &&
            dark &&
            const bool.fromEnvironment('UI_CURRENT_TYPOGRAPHY_HOLD')) {
          debugPrint('TYPOGRAPHY_BUSINESS_REDESIGN_DARK_AR');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 12)));
        }
        await reveal(tester, field('phone'));
        if (!const bool.fromEnvironment('UI_BUSINESS_TOP_ONLY')) {
          await currentTypographyCheckpoint(
              tester, 'BUSINESS_REDESIGN_CONTACT');
        }
        await reveal(tester, field('logo_picker'));
        if (!const bool.fromEnvironment('UI_BUSINESS_TOP_ONLY')) {
          await currentTypographyCheckpoint(tester, 'BUSINESS_REDESIGN_MEDIA');
        }
        await reveal(tester, find.byType(RadioListTile<String>));
        await tester.tap(find.byType(RadioListTile<String>));
        await frames(tester);
        expect(find.text(t('ui_ad_placements')), findsOneWidget);
        for (final placement in ['Home', 'Business directory']) {
          expect(find.text(placement), findsOneWidget);
          expect(tester.widget<Text>(find.text(placement)).textDirection,
              TextDirection.ltr);
        }
        if (!const bool.fromEnvironment('UI_BUSINESS_TOP_ONLY')) {
          await currentTypographyCheckpoint(
              tester, 'BUSINESS_PACKAGE_PLACEMENTS');
        }
        expect(tester.takeException(), isNull);
        expect(f.uploads, isEmpty);
        expect(f.writes('business_ads'), isEmpty);
        await finish(tester);
      });
      testWidgets(
          'Business request ${locale.code} dark=$dark enlarged partial-order recovery layout',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        f.failTable = 'business_ads';
        await mount(tester);
        await fill(tester);
        await send(tester);
        expect(find.text(t('ui_business_submit_failed')), findsOneWidget);
        expect(find.text(t('ui_business_resume_note')), findsOneWidget);
        expect(find.text(t('ui_retry')).hitTestable(), findsOneWidget);
        expect(f.writes('business_ads').length, 1);
        expect(f.writes('business_ad_orders').length, 0);
        expect(f.uploads.length, 3);
        expect(find.byType(PaymentPageSubmitted), findsNothing);
        expect(find.textContaining('private'), findsNothing);
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(
              tester, 'BUSINESS_SUBMISSION_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'BUSINESS_CREATE_RECOVERY');
        }
        await reveal(tester, field('logo_picker'));
        expect(tester.widget<InkWell>(field('logo_picker')).onTap, isNull);
        expect(find.byType(Image), findsWidgets);
        final remove = find.byTooltip(t('common_delete')).first;
        await reveal(tester, remove);
        final removeButton =
            find.ancestor(of: remove, matching: find.byType(IconButton)).first;
        expect(tester.widget<IconButton>(removeButton).onPressed, isNull);
        final imageCount = find.byType(Image).evaluate().length;
        await tester.tap(remove);
        await frames(tester);
        expect(find.byType(Image).evaluate().length, imageCount);
        expect(f.uploads.length, 3);
        expect(f.writes('business_ads').length, 1);
        expect(f.writes('business_ad_orders').length, 0);
        await currentTypographyCheckpoint(tester, 'BUSINESS_LOCKED_MEDIA');
        if (locale == AppLocale.ar && !dark || locale == AppLocale.ku && dark) {
          await hold(tester, 'BUSINESS_MEDIA_${locale.code.toUpperCase()}');
          await currentTypographyCheckpoint(tester, 'BUSINESS_CREATE_MEDIA');
        }
        await reveal(tester, field('name'));
        expect(tester.widget<TextFormField>(field('name')).enabled, isFalse);
        expect(tester.widget<TextFormField>(field('name')).controller!.text,
            isNotEmpty);
        await finish(tester);
      });
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Business draft direction ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        await mount(tester, width: 320);
        await currentTypographyCheckpoint(tester, 'BUSINESS_CREATE_FORM');
        for (final key in ['name', 'description', 'area', 'address', 'hours']) {
          await reveal(tester, field(key));
          final controller =
              tester.widget<TextFormField>(field(key)).controller!;
          const value = TextEditingValue(
              text: 'خدمة Toyota',
              selection: TextSelection.collapsed(offset: 2),
              composing: TextRange(start: 0, end: 4));
          controller.value = value;
          await tester.pump();
          final input =
              find.descendant(of: field(key), matching: find.byType(TextField));
          expect(
              tester.widget<TextField>(input).textDirection, TextDirection.rtl);
          expect(controller.value, value);
          controller.text = 'Toyota خدمة';
          await tester.pump();
          expect(
              tester.widget<TextField>(input).textDirection, TextDirection.ltr);
        }
        await input(tester, 'hours', '09:00 – 18:00');
        expect(
            tester
                .widget<TextField>(find.descendant(
                    of: field('hours'), matching: find.byType(TextField)))
                .textDirection,
            TextDirection.ltr);
        await reveal(tester, find.byType(RadioListTile<String>));
        await tester.tap(find.byType(RadioListTile<String>));
        await frames(tester);
        await currentTypographyCheckpoint(tester, 'BUSINESS_CREATE_PACKAGE');
        await fill(tester);
        await input(tester, 'name', 'Toyota خدمة');
        await review(tester);
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
            tester
                .widget<Text>(find.descendant(
                    of: find.byType(AlertDialog),
                    matching: find.text('Toyota خدمة')))
                .textDirection,
            TextDirection.ltr);
        await currentTypographyCheckpoint(tester, 'BUSINESS_CREATE_CONFIRM');
        await tester.tap(find.text(t('common_cancel')));
        await frames(tester);
        expect(f.requests, isEmpty);
        await finish(tester);
      });
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets(
          'Business package recovery ${locale.code} dark=$dark enlarged',
          (tester) async {
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        f.packageGate = Completer<void>();
        await mount(tester, width: 320);
        await input(tester, 'name', 'Toyota خدمة');
        await reveal(tester, find.byType(CircularProgressIndicator));
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'BUSINESS_PACKAGE_LOADING');
        f.failPackages = true;
        f.packageGate!.complete();
        await frames(tester);
        await reveal(tester, find.text(t('ui_retry')));
        expect(find.textContaining('private'), findsNothing);
        await currentTypographyCheckpoint(tester, 'BUSINESS_PACKAGE_ERROR');
        f.failPackages = false;
        f.emptyPackages = true;
        await tester.tap(find.text(t('ui_retry')));
        await frames(tester);
        expect(find.text(t('pkg_none_available')), findsOneWidget);
        await currentTypographyCheckpoint(tester, 'BUSINESS_PACKAGE_EMPTY');
        expect(tester.widget<TextFormField>(field('name')).controller!.text,
            'Toyota خدمة');
        expect(f.requests, isEmpty);
        await finish(tester);
      });
    }
  }
  for (final locale in [AppLocale.ar, AppLocale.ku]) {
    testWidgets('Business contact fields ${locale.code}', (tester) async {
      appLocaleNotifier.value = locale;
      AppColors.isDark = locale == AppLocale.ku;
      await mount(tester);
      await input(tester, 'whatsapp', '07701234567');
      await input(tester, 'maps', 'https://maps.example.com/business');
      await reveal(tester, field('whatsapp'));
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: field('whatsapp'), matching: find.byType(TextField)))
              .textDirection,
          TextDirection.ltr);
      expect(field('whatsapp').hitTestable(), findsOneWidget);
      await hold(tester, 'BUSINESS_CONTACT_${locale.code.toUpperCase()}');
      expect(f.requests, isEmpty);
      expect(f.uploads, isEmpty);
      await finish(tester);
    });
  }
  testWidgets(
      'Business transaction retry reaches payment without another upload',
      (tester) async {
    appLocaleNotifier.value = AppLocale.ar;
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeMount] test=retry session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeMount] test=retry err=$e');
    }
    f.failTable = 'business_ads';
    await mount(tester);
    await fill(tester);
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeSend] test=retry session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeSend] test=retry err=$e');
    }
    await send(tester);
    expect(find.text(t('ui_business_submit_failed')), findsOneWidget);
    expect(find.text(t('ui_retry')).hitTestable(), findsOneWidget);
    f.failTable = null;
    await tester.tap(find.text(t('ui_retry')).hitTestable().last);
    await frames(tester);
    expect(find.byType(PaymentPageSubmitted), findsOneWidget);
    expect(f.writes('business_ads').length, 2);
    expect(f.orders.length, 0);
    expect(f.uploads.length, 3);
    await finish(tester);
  });
  testWidgets(
      'Business lost ad acknowledgement resumes the confirmed original request',
      (tester) async {
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeMount] test=lostAck session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeMount] test=lostAck err=$e');
    }
    f.emptyAck = 'business_ads';
    await mount(tester);
    await fill(tester);
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeSend] test=lostAck session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeSend] test=lostAck err=$e');
    }
    await send(tester);
    expect(find.byType(PaymentPageSubmitted), findsNothing);
    final firstWrites = f.writes('business_ads').length;
    final firstAdId = firstWrites > 0 ? jsonDecode(f.writes('business_ads').first.body)['ad_id'] : null;
    f.emptyAck = null;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.byType(PaymentPageSubmitted), findsOneWidget);
    expect(f.writes('business_ads').length, 2);
    final secondWrites = f.writes('business_ads');
    expect(secondWrites.length, 2);
    final secondAdId = jsonDecode(secondWrites.last.body)['ad_id'];
    expect(firstAdId, isNotNull);
    expect(secondAdId, firstAdId);
    expect(f.orders.length, 0);
    await finish(tester);
  });
  testWidgets(
      'Business upload retry keeps completed logo and permits draft edits before inserting',
      (tester) async {
    f.failUploadAt = 2;
    await mount(tester);
    await fill(tester);
    await send(tester);
    expect(find.text(t('ui_business_upload_failed')), findsOneWidget);
    expect(f.requests, isEmpty);
    final failedPath = f.uploads.last.url.path;
    f.failUploadAt = 0;
    await input(tester, 'name', 'Edited before upload retry');
    await send(tester);
    expect(find.byType(PaymentPageSubmitted), findsOneWidget);
    expect(f.uploads.length, 4);
    expect(f.uploads[2].url.path, failedPath);
    expect(f.ads.values.single['business_name'], 'Edited before upload retry');
    await finish(tester);
  });
  testWidgets(
      'Business normal form and concrete confirmation can cancel without writes',
      (tester) async {
    await mount(tester, scale: 1, width: 900);
    await fill(tester);
    await reveal(tester, field('name'));
    expect(tester.getSize(find.byType(SingleChildScrollView).first).width,
        lessThanOrEqualTo(760));
    await hold(tester, 'BUSINESS_FORM_REGULAR');
    await review(tester);
    expect(find.textContaining('Visibility package'), findsWidgets);
    expect(find.textContaining('USD'), findsWidgets);
    await hold(tester, 'BUSINESS_REVIEW_REGULAR');
    await tester.tap(find.text(t('common_cancel')));
    await frames(tester);
    expect(f.uploads, isEmpty);
    expect(f.requests, isEmpty);
    await finish(tester);
  });
  testWidgets(
      'Business validates offscreen required fields and malformed URLs before uploading',
      (tester) async {
    await mount(tester);
    await reveal(tester, find.text(t('confirm_review')));
    await tester.tap(find.text(t('confirm_review')));
    await frames(tester);
    expect(find.text(t('ui_business_check_fields')), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    await input(tester, 'name', 'x' * 101);
    await reveal(tester, find.text(t('confirm_review')));
    await tester.tap(find.text(t('confirm_review')));
    await frames(tester);
    expect(f.uploads, isEmpty);
    await input(tester, 'name', 'MOTRI Service');
    await input(tester, 'maps', 'https://');
    await reveal(tester, find.text(t('confirm_review')));
    await tester.tap(find.text(t('confirm_review')));
    await frames(tester);
    expect(find.text(t('ui_business_check_fields')), findsOneWidget);
    expect(f.requests, isEmpty);
    await finish(tester);
  });
  testWidgets(
      'Business invalid picker feedback remains visible alongside failed packages',
      (tester) async {
    f.failPackages = true;
    corrupt = true;
    await mount(tester);
    await reveal(tester, field('logo_picker'));
    await tester.tap(field('logo_picker'));
    await frames(tester);
    expect(find.text(t('ui_business_photo_failed')), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    expect(f.uploads, isEmpty);
    await finish(tester);
  });
  testWidgets('Business media cap and removal stay consistent', (tester) async {
    photoCount = 7;
    await mount(tester);
    await reveal(tester, field('images_picker'));
    await tester.tap(field('images_picker'));
    await frames(tester);
    expect(find.byWidgetPredicate((w) => w is Image && w.width == 90),
        findsNWidgets(5));
    expect(field('images_picker'), findsNothing);
    final remove = find.byTooltip(t('common_delete')).first;
    expect(tester.getSize(remove).shortestSide, greaterThanOrEqualTo(44));
    await tester.tap(remove);
    await frames(tester);
    expect(field('images_picker'), findsOneWidget);
    await finish(tester);
  });
  testWidgets('Business picker pending guard and disposal prevent late changes',
      (tester) async {
    pickerGate = Completer<void>();
    await mount(tester);
    await reveal(tester, field('logo_picker'));
    await tester.tap(field('logo_picker'));
    await frames(tester);
    expect(tester.widget<InkWell>(field('logo_picker')).onTap, isNull);
    expect(logoCalls, 1);
    await tester.pumpWidget(const SizedBox());
    pickerGate!.complete();
    await frames(tester);
    expect(f.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Business pending upload blocks back and disposal prevents inserts',
      (tester) async {
    f.uploadGate = Completer<void>();
    await mount(tester);
    await fill(tester);
    await send(tester);
    expect(find.text(t('img_uploading')), findsOneWidget);
    expect(tester.widget<PopScope>(find.byType(PopScope).last).canPop, isFalse);
    await tester.pumpWidget(const SizedBox());
    f.uploadGate!.complete();
    await frames(tester);
    expect(f.requests, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'Business session loss during upload keeps request from another account',
      (tester) async {
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeMount] test=sessionLoss session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeMount] test=sessionLoss err=$e');
    }
    f.uploadGate = Completer<void>();
    await mount(tester);
    await fill(tester);
    try {
      final s = backendAuthSession;
      debugPrint('[DIAG][beforeSend] test=sessionLoss session=${s.user?.id}');
    } catch (e) {
      debugPrint('[DIAG][beforeSend] test=sessionLoss err=$e');
    }
    await send(tester);
    await tester
        .runAsync(() => backendAuthSession.logout());
    await tester.runAsync(() => f.client.auth.signOut());
    f.uploadGate!.complete();
    await frames(tester);
    expect(find.text(t('ui_business_session_changed')), findsOneWidget);
    expect(f.requests, isEmpty);
    await tester.runAsync(f.signIn);
    await finish(tester);
  });
}
