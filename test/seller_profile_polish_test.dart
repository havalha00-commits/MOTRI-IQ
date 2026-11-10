import 'package:motri_iq/market_images.dart';
import 'support/current_typography_checkpoint.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/ui/seller_profile_header.dart';
import 'package:motri_iq/ui/seller_rating_dialog.dart';

Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  const viewerId = '00000000-0000-4000-8000-000000000001';
  const sellerId = '00000000-0000-4000-8000-000000000002';
  var failRead = false,
      populated = true,
      failReview = false,
      reviewWrites = 0,
      offerWrites = 0;
  var invalidPhone = false, includeFavorites = false;
  var mixedFavorites = false;
  Uri? marketRead;
  const photoUrl =
      'https://frfqpxviebzkyvppuzdb.supabase.co/storage/v1/object/public/cars/14f652d6-e797-4c38-980c-e535c10d36b2/seed_cars/chery_arrizo_5.jpg';
  String marketTitle() => appLocale == AppLocale.ar
      ? 'مجموعة إطارات أصلية للعائلة مع تجهيزات إضافية للسيارة'
      : appLocale == AppLocale.ku
          ? 'کۆمەڵە تایەی ڕەسەن و کەرەستەی زیاتر بۆ ئۆتۆمبێلی خێزانی'
          : 'Original family vehicle tyres and additional automotive equipment';
  var offerStatus = 'pending';
  Map<String, dynamic>? savedReview;
  Completer<void>? offerGate, offerReadGate, profileReadGate;
  var failOffer = false, missingOfferAck = false;
  http.Response response(http.Request req, Object? body, {int status = 200}) =>
      http.Response(jsonEncode(body), status,
          request: req,
          headers: {'content-type': 'application/json; charset=utf-8'});
  Future<void> signIn() => Supabase.instance.client.auth
      .signInWithPassword(email: 'fixture@example.com', password: 'local-only')
      .then((_) {});
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final payload = base64Url
        .encode(utf8.encode(jsonEncode({
          'sub': viewerId,
          'role': 'authenticated',
          'exp': DateTime.now()
                  .add(const Duration(hours: 1))
                  .millisecondsSinceEpoch ~/
              1000
        })))
        .replaceAll('=', '');
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        httpClient: MockClient((req) async {
          final table = req.url.path.split('/').last;
          final filter = req.url.queryParameters['seller_id'] ??
              req.url.queryParameters['user_id'] ??
              '';
          final rowSeller = filter.contains(viewerId) ? viewerId : sellerId;
          if (req.url.path == '/auth/v1/token') {
            return response(req, {
              'access_token': 'eyJhbGciOiJIUzI1NiJ9.$payload.fixture',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': viewerId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            });
          }
          if (req.url.path == '/auth/v1/logout') return response(req, {});
          if (table == 'seller_reviews' && req.method == 'POST') {
            reviewWrites++;
            savedReview = jsonDecode(req.body) as Map<String, dynamic>;
            return response(
                req,
                failReview
                    ? {'message': 'Private fixture review exception'}
                    : null,
                status: failReview ? 400 : 200);
          }
          if (table == 'car_offers' && req.method == 'PATCH') {
            offerWrites++;
            if (offerGate != null) await offerGate!.future;
            if (failOffer) {
              return response(
                  req, {'message': 'Private fixture offer exception'},
                  status: 400);
            }
            offerStatus = (jsonDecode(req.body) as Map)['status'] as String;
            return response(
                req, missingOfferAck ? null : {'id': 'fixture-offer'});
          }
          expectSync(req.method, 'GET',
              reason:
                  'Only isolated review/offer fixture mutations are permitted');
          if (table == 'cars_public') await profileReadGate?.future;
          if (failRead && table == 'cars_public') {
            return response(req, {'message': 'Private fixture read exception'},
                status: 400);
          }
          if (table == 'car_offers') await offerReadGate?.future;
          Object body = [];
          if (includeFavorites && table == 'favorites') {
            body = [
              {
                'car_id': 'profile-car',
                'item_type': 'car',
                'item_id': 'profile-car'
              },
              if (mixedFavorites)
                {
                  'car_id': null,
                  'item_type': 'market',
                  'item_id': 'saved-market'
                }
            ];
          }
          if (populated) {
            if (table == 'cars_public') {
              body = [
                {
                  'id': 'profile-car',
                  'user_id': rowSeller,
                  'brand': 'MOTRI',
                  'model': 'Family utility vehicle',
                  'year': 2025,
                  'price': 25000,
                  'province': 'Baghdad',
                  'city': 'Mansour',
                  'status': 'active',
                  if (mixedFavorites &&
                      const bool.fromEnvironment('NATIVE_VIEWPORT'))
                    'image_url': jsonEncode([photoUrl])
                }
              ];
            }
            if (mixedFavorites && table == 'market_items') {
              marketRead = req.url;
              body = [
                {
                  'id': 'saved-market',
                  'title': marketTitle(),
                  'price': 150,
                  'city': 'Baghdad',
                  'description':
                      'Original tyres and useful automotive equipment.',
                  if (const bool.fromEnvironment('NATIVE_VIEWPORT'))
                    'images': [photoUrl],
                }
              ];
            }
            if (table == 'seller_reviews') {
              body = [
                for (var i = 0; i < 10; i++)
                  {
                    'rating': 5,
                    'seller_id': rowSeller,
                    'comment': 'Detailed review $i from a local buyer.'
                  }
              ];
            }
            if (table == 'seller_showrooms') {
              body = {
                'showroom_name':
                    'MOTRI automotive showroom and family vehicle specialists',
                'city': 'Baghdad',
                'province': ' Baghdad ',
                'contact_phone':
                    invalidPhone ? 'invalid contact' : '٠٧٧١٥٣٣٩٩٢٢',
                'description':
                    'Find your next family vehicle with our local team.'
              };
            }
            if (table == 'seller_verifications') {
              body = req.url.queryParameters['seller_id']?.startsWith('eq.') ==
                      true
                  ? {'seller_id': rowSeller}
                  : [
                      {'seller_id': rowSeller}
                    ];
            }
            if (table == 'car_offers') {
              body = [
                {
                  'id': 'fixture-offer',
                  'car_title': 'Family vehicle with a long model name',
                  'offer_price': 22000,
                  'message': 'I would like to inspect this vehicle this week.',
                  'status': offerStatus
                }
              ];
            }
          }
          return response(req, body);
        }));
    await signIn();
  });
  setUp(() async {
    await signIn();
  });
  tearDown(() {
    missingOfferAck = false;
    failRead = false;
    populated = true;
    failReview = false;
    reviewWrites = 0;
    offerWrites = 0;
    failOffer = false;
    offerGate = null;
    offerReadGate = null;
    profileReadGate = null;
    offerStatus = 'pending';
    savedReview = null;
    invalidPhone = false;
    includeFavorites = false;
    mixedFavorites = false;
    marketRead = null;
    trustCache.reset();
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
  });
  tearDownAll(
      () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));

  Widget host(AppLocale locale, bool dark, {bool own = false, Widget? page}) {
    AppColors.isDark = dark;
    return MaterialApp(
      key: UniqueKey(),
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
      locale: locale.locale,
      supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
      localizationsDelegates: appLocalizationsDelegates,
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(1.6)),
          child: child!),
      home: page ??
          SellerProfilePage(
              sellerId: own ? viewerId : sellerId, sellerName: 'MOTRI seller'),
    );
  }

  void size(WidgetTester tester) {
    if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
      tester.view.physicalSize = const Size(320, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
  }

  testWidgets('initial delayed seller read shows loading before profile',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.ar;
    AppColors.isDark = false;
    profileReadGate = Completer<void>();
    await tester.pumpWidget(host(AppLocale.ar, false));
    await frames(tester);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(SellerProfileHeader), findsNothing);
    expect(find.text(t('ui_load_error_title')), findsNothing);
    await currentTypographyCheckpoint(tester, 'SELLER_INITIAL_LOADING');
    profileReadGate!.complete();
    await frames(tester);
    expect(find.byType(SellerProfileHeader), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      for (final own in [false, true]) {
        testWidgets(
            '${locale.code} seller profile populated own=$own dark=$dark',
            (tester) async {
          size(tester);
          appLocaleNotifier.value = locale;
          AppColors.isDark = dark;
          await tester.pumpWidget(host(locale, dark, own: own));
          await frames(tester);
          expect(find.byType(SellerProfileHeader), findsOneWidget);
          expect(find.text(t('seller_verified')), findsOneWidget);
          expect(find.text('Baghdad'), findsOneWidget);
          expect(find.text(t('ui_profile_one_listing')), findsOneWidget);
          expect(tester.takeException(), isNull);
          if (!own) await currentTypographyCheckpoint(tester, 'PROFILE');
          if (own) {
            final title = find.text('Family vehicle with a long model name');
            await tester.scrollUntilVisible(title, 300,
                scrollable: find.byType(Scrollable).first, maxScrolls: 20);
            await Scrollable.ensureVisible(tester.element(title),
                alignment: .05);
            await frames(tester);
            expect(title.hitTestable(), findsOneWidget);
            await currentTypographyCheckpoint(tester, 'PROFILE_OFFERS');
          }
          if (const bool.fromEnvironment('UI_PROFILE_REVIEW_HOLD') &&
              locale == AppLocale.en &&
              dark &&
              !own) {
            debugPrint('UI_PROFILE_REVIEW_READY');
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(seconds: 15)));
          }
          await tester.scrollUntilVisible(
              find.text('Detailed review 9 from a local buyer.'), 350,
              scrollable: find.byType(Scrollable).first, maxScrolls: 30);
          await frames(tester);
          expect(tester.takeException(), isNull);
          expect(find.text('Detailed review 9 from a local buyer.'),
              findsOneWidget);
          await tester.pumpWidget(const SizedBox.shrink());
          await frames(tester);
        });
      }
    }
    testWidgets('${locale.code} seller load failure retries into empty profile',
        (tester) async {
      size(tester);
      appLocaleNotifier.value = locale;
      failRead = true;
      populated = false;
      await tester.pumpWidget(host(locale, false));
      await frames(tester);
      expect(find.text(t('ui_load_error_title')), findsOneWidget);
      expect(find.textContaining('Private fixture'), findsNothing);
      failRead = false;
      await tester.tap(find.text(t('ui_retry')));
      await frames(tester);
      expect(find.byType(SellerProfileHeader), findsOneWidget);
      await tester.scrollUntilVisible(
          find.text(t('account_no_reviews_now')), 250,
          scrollable: find.byType(Scrollable).first);
      await frames(tester);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
  }
  testWidgets('review failure retains draft; retry saves the selected rating',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    failReview = true;
    await tester.pumpWidget(host(AppLocale.en, false));
    await frames(tester);
    final add = find.text(t('review_add'));
    for (var i = 0; i < 15 && add.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await frames(tester);
    }
    expect(add.hitTestable(), findsOneWidget);
    await tester.tap(add);
    await frames(tester);
    await tester
        .tap(find.byTooltip(t('ui_rating_choice').replaceAll('{rating}', '3')));
    await tester.enterText(find.byType(TextField), 'A detailed draft review');
    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await frames(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text(t('common_send')));
    await frames(tester);
    tester.view.resetViewInsets();
    await frames(tester);
    expect(reviewWrites, 1);
    expect(find.text(t('review_save_failed')), findsOneWidget);
    expect(find.textContaining('Private fixture'), findsNothing);
    failReview = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.text('A detailed draft review'), findsOneWidget);
    await tester.tap(find.text(t('common_send')));
    await frames(tester);
    expect(reviewWrites, 2);
    expect(savedReview!['rating'], 3);
    expect(savedReview!['comment'], 'A detailed draft review');
    expect(find.text(t('ui_review_saved')), findsOneWidget);
    expect(find.byType(SellerRatingDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
  });
  testWidgets(
      'received offer prevents duplicate writes and recovers after failure',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    await tester.pumpWidget(host(AppLocale.en, true, own: true));
    await frames(tester);
    expect(find.text(t('review_add')), findsNothing);
    final reject = find.text(t('offer_reject'));
    await tester.scrollUntilVisible(reject, 350,
        scrollable: find.byType(Scrollable).first, maxScrolls: 20);
    await tester.ensureVisible(reject);
    await frames(tester);
    offerGate = Completer<void>();
    failOffer = true;
    await tester.tap(reject);
    await frames(tester);
    expect(offerWrites, 1);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, t('offer_reject')))
            .onPressed,
        isNull);
    offerGate!.complete();
    await frames(tester);
    expect(find.text(t('offer_update_failed')), findsOneWidget);
    expect(find.textContaining('Private fixture'), findsNothing);
    offerGate = null;
    failOffer = false;
    await tester.tap(reject);
    await frames(tester);
    expect(offerWrites, 2);
    await tester.scrollUntilVisible(
        find.text('${t('offer_status')}: ${t('offer_rejected')}'), 250,
        scrollable: find.byType(Scrollable).first, maxScrolls: 20);
    expect(find.text(t('offer_reject')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
  });
  for (final locale in AppLocale.values) {
    testWidgets('${locale.code} rating cancel is safe above the keyboard',
        (tester) async {
      size(tester);
      appLocaleNotifier.value = locale;
      var completed = false;
      await tester.pumpWidget(host(locale, locale == AppLocale.ku,
          page: Scaffold(
              body: Builder(
                  builder: (context) => Center(
                      child: TextButton(
                          onPressed: () async {
                            await showDialog<SellerRatingDraft>(
                                context: context,
                                builder: (_) => Directionality(
                                    textDirection: locale.direction,
                                    child: SellerRatingDialog(
                                        title: t('rate_seller'),
                                        commentLabel:
                                            t('field_optional_comment'),
                                        cancelLabel: t('common_cancel'),
                                        sendLabel: t('common_send'),
                                        ratingLabel: (rating) =>
                                            t('ui_rating_choice').replaceAll(
                                                '{rating}', '$rating'))));
                            completed = true;
                          },
                          child: const Text('Open rating')))))));
      await frames(tester);
      await tester.tap(find.text('Open rating'));
      await frames(tester);
      await tester.enterText(find.byType(TextField), 'Draft');
      if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
      } else {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)));
      }
      await frames(tester);
      expect(tester.takeException(), isNull);
      final keyboard =
          tester.view.viewInsets.bottom / tester.view.devicePixelRatio;
      expect(keyboard, greaterThan(0));
      expect(
          tester.getBottomRight(find.text(t('common_cancel'))).dy,
          lessThanOrEqualTo(
              tester.view.physicalSize.height / tester.view.devicePixelRatio -
                  keyboard));
      await currentTypographyCheckpoint(tester, 'PROFILE_RATING');
      await tester.tap(find.text(t('common_cancel')));
      await tester.pumpAndSettle();
      expect(completed, isTrue);
      expect(find.byType(SellerRatingDialog), findsNothing);
      expect(reviewWrites, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames(tester);
    });
  }
  testWidgets(
      'guest review explains sign-in and invalid showroom contact stays hidden',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    invalidPhone = true;
    await tester.runAsync(
        () => Supabase.instance.client.auth.signOut(scope: SignOutScope.local));
    await tester.pumpWidget(host(AppLocale.en, false));
    await frames(tester);
    expect(find.text(t('support_whatsapp')), findsNothing);
    final add = find.text(t('review_add'));
    for (var i = 0; i < 15 && add.hitTestable().evaluate().isEmpty; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await frames(tester);
    }
    expect(add.hitTestable(), findsOneWidget);
    await tester.tap(add);
    await frames(tester);
    expect(find.text(t('misc_login_to_rate')), findsOneWidget);
    expect(find.byType(SellerRatingDialog), findsNothing);
    expect(reviewWrites, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
    await tester.runAsync(signIn);
  });
  testWidgets('profile pull-to-refresh failure exposes a recoverable error',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    await tester.pumpWidget(host(AppLocale.en, false));
    await frames(tester);
    failRead = true;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    for (var i = 0; i < 4; i++) {
      await frames(tester);
    }
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    failRead = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.byType(SellerProfileHeader), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('${locale.code} populated favorites dark=$dark',
          (tester) async {
        size(tester);
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        includeFavorites = true;
        await tester
            .pumpWidget(host(locale, dark, page: const FavoritesPage()));
        await frames(tester);
        expect(find.byType(CarCard), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await frames(tester);
      });
    }
  }
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('${locale.code} mixed favorites dark=$dark', (tester) async {
        size(tester);
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        includeFavorites = mixedFavorites = true;
        await tester
            .pumpWidget(host(locale, dark, page: const FavoritesPage()));
        await frames(tester);
        expect(find.byType(CarCard), findsOneWidget);
        expect(marketRead!.queryParameters['id'], contains('saved-market'));
        if (const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          expect(carImageUrls(tester.widget<CarCard>(find.byType(CarCard)).car),
              [photoUrl]);
          Object? imageError;
          await tester.runAsync(() => precacheImage(NetworkImage(photoUrl),
                  tester.element(find.byType(FavoritesPage)),
                  onError: (error, stack) => imageError = error)
              .timeout(const Duration(seconds: 25)));
          expect(imageError, isNull,
              reason: 'Loaded photos are required for mixed Favorites review');
          final decoded = find.descendant(
              of: find.byType(CarCard),
              matching: find
                  .byWidgetPredicate((w) => w is RawImage && w.image != null));
          for (var attempt = 0;
              attempt < 60 && decoded.evaluate().isEmpty;
              attempt++) {
            await tester.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)));
            await frames(tester);
          }
          expect(decoded, findsWidgets,
              reason:
                  'Capture a decoded card image, not its loading placeholder');
          await tester.pump(const Duration(milliseconds: 300));
          await frames(tester);
        }
        await currentTypographyCheckpoint(tester, 'FAVORITES_CARS');
        await tester.scrollUntilVisible(find.byType(GenericAdCard), 280,
            scrollable: find.byType(Scrollable).first);
        await Scrollable.ensureVisible(
            tester.element(find.byType(GenericAdCard)),
            alignment: .15);
        await frames(tester);
        expect(find.text(marketTitle()), findsOneWidget);
        expect(tester.takeException(), isNull);
        await currentTypographyCheckpoint(tester, 'FAVORITES_MARKET');
        await tester.tap(find.byType(GenericAdCard));
        await frames(tester);
        expect(find.byType(MarketItemDetailsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(BackButton));
        await frames(tester);
        expect(find.byType(FavoritesPage), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await frames(tester);
      });
    }
  }
  testWidgets('favorites read failure is retryable rather than an empty list',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    includeFavorites = true;
    failRead = true;
    await tester
        .pumpWidget(host(AppLocale.en, false, page: const FavoritesPage()));
    await frames(tester);
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(find.text(t('account_no_saved_ads')), findsNothing);
    expect(find.textContaining('Private fixture'), findsNothing);
    failRead = false;
    await tester.tap(find.text(t('ui_retry')));
    await frames(tester);
    expect(find.byType(CarCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    failRead = true;
    await tester.drag(find.byType(GridView), const Offset(0, 500));
    for (var i = 0; i < 4; i++) {
      await frames(tester);
    }
    expect(find.text(t('ui_load_error_title')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await frames(tester);
  });
  testWidgets('seller pending review dialog cannot submit after logout',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    await tester.pumpWidget(host(AppLocale.en, false));
    await frames(tester);
    final add = find.text(t('review_add'));
    await tester.scrollUntilVisible(add, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(add);
    await frames(tester);
    await tester.tap(add);
    await frames(tester);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    await frames(tester);
    await tester.tap(find.text(t('common_send')));
    await frames(tester);
    expect(reviewWrites, 0);
    expect(find.text(t('ui_review_saved')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  for (final logout in [false, true]) {
    testWidgets(
        'seller offer requires acknowledgement and current account logout=$logout',
        (tester) async {
      size(tester);
      appLocaleNotifier.value = AppLocale.en;
      await tester.pumpWidget(host(AppLocale.en, true, own: true));
      await frames(tester);
      final accept = find.text(t('offer_accept'));
      await tester.scrollUntilVisible(accept, 350,
          scrollable: find.byType(Scrollable).first, maxScrolls: 20);
      await tester.ensureVisible(accept);
      await frames(tester);
      missingOfferAck = true;
      if (logout) offerGate = Completer<void>();
      await tester.tap(accept);
      await frames(tester);
      if (logout) {
        await tester
            .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
        offerGate!.complete();
        await frames(tester);
      } else {
        expect(find.text(t('offer_update_failed')), findsOneWidget);
      }
      expect(find.byType(CarOfferChatPage), findsNothing);
      expect(offerWrites, 1);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('seller late owner offers cannot reappear after logout',
      (tester) async {
    size(tester);
    appLocaleNotifier.value = AppLocale.en;
    offerReadGate = Completer<void>();
    await tester.pumpWidget(host(AppLocale.en, false, own: true));
    await frames(tester);
    await tester
        .runAsync(() => supabase.auth.signOut(scope: SignOutScope.local));
    offerReadGate!.complete();
    await frames(tester);
    expect(find.text(t('account_received_offers')), findsNothing);
    expect(find.text(t('offer_accept')), findsNothing);
    expect(find.byType(SellerProfileHeader), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
