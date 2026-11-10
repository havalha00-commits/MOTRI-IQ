import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'test',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((request) async {
          expectSync(request.method, 'GET');
          return http.Response('[]', 200,
              headers: {'content-type': 'application/json'}, request: request);
        }));
  });
  tearDown(() => appLocaleNotifier.value = AppLocale.ar);
  test('currency conversion keeps existing values and isolates the numeric run',
      () {
    expect(formatCurrency(25), '\u206625\u00a0USD • 32,750\u00a0IQD\u2069');
    expect(formatIqd(10000), '\u206610,000\u00a0IQD\u2069');
    expect(formatCurrency(0), '\u20660\u00a0USD • 0\u00a0IQD\u2069');
  });
  test('localized digits and separators produce the same price', () {
    for (final input in ['25,000', '٢٥٬٠٠٠', '۲۵٬۰۰۰']) {
      expect(formatPriceDisplay(input), formatCurrency(25000));
      expect(formatPriceDisplayCompact(input),
          '\u206625,000\u00a0USD / 32,750,000\u00a0IQD\u2069');
    }
  });
  test('large finite input cannot overflow converted display', () {
    expect(formatCurrency(1e308), t('compare_price_unknown'));
    expect(formatCurrencyLines(1e308), t('compare_price_unknown'));
    expect(formatPriceDisplayCompact('1e308'), t('compare_price_unknown'));
    expect(formatUsd(double.infinity), t('compare_price_unknown'));
  });
  test('currency units stay with amounts at a line break', () {
    final value = formatCurrency(25000);
    final painter = TextPainter(
        text: TextSpan(text: value, style: const TextStyle(fontSize: 24)),
        textDirection: TextDirection.ltr)
      ..layout(maxWidth: 380);
    for (final suffix in ['USD', 'IQD']) {
      final code = value.indexOf(suffix), space = code - 1;
      expect(value[space], '\u00a0');
      final digit = painter
          .getBoxesForSelection(
              TextSelection(baseOffset: space - 1, extentOffset: space))
          .first;
      final unit = painter
          .getBoxesForSelection(
              TextSelection(baseOffset: code, extentOffset: code + 3))
          .first;
      expect(digit.top, unit.top);
    }
    painter.dispose();
  });
  test('non-numeric price labels do not acquire a currency', () {
    expect(formatPriceDisplayCompact('Negotiable'), 'Negotiable');
    expect(formatPriceDisplay('السعر عند الاتصال'), 'السعر عند الاتصال');
    expect(formatPriceDisplay('NaN'), t('compare_price_unknown'));
    expect(formatCurrency(double.infinity), t('compare_price_unknown'));
  });
  for (final locale in AppLocale.values) {
    test('${locale.code} numeric currency order survives surrounding prose',
        () {
      appLocaleNotifier.value = locale;
      final value = '${t('field_price')}: ${formatCurrency(25)}';
      final painter = TextPainter(
          text: TextSpan(text: value, style: const TextStyle(fontSize: 20)),
          textDirection: locale.direction)
        ..layout(maxWidth: 1200);
      final usd = value.indexOf('25\u00a0USD'),
          iqd = value.indexOf('32,750\u00a0IQD');
      final usdBox = painter
          .getBoxesForSelection(
              TextSelection(baseOffset: usd, extentOffset: usd + 6))
          .first;
      final iqdBox = painter
          .getBoxesForSelection(
              TextSelection(baseOffset: iqd, extentOffset: iqd + 10))
          .first;
      expect(usdBox.left, lessThan(iqdBox.left));
      painter.dispose();
    });
    for (final dark in [false, true]) {
      testWidgets('${locale.code} shared price surfaces dark=$dark large text',
          (tester) async {
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.physicalSize = const Size(320, 720);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        final package = BusinessAdPackage(
            id: 'pkg',
            name: 'Package',
            durationDays: 30,
            price: 25,
            placements: [],
            features: [],
            isActive: true);
        await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(dark ? Brightness.dark : Brightness.light),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.6)),
                child: child!),
            home: Directionality(
                textDirection: locale.direction,
                child: Scaffold(
                    body: SafeArea(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                      '${t('wallet_pending')}: ${formatIqd(10000)}'),
                                  const SizedBox(height: 12),
                                  Text(package.priceText),
                                  const SizedBox(height: 16),
                                  const CarCard(car: {
                                    'id': 'currency-car',
                                    'brand': 'Toyota',
                                    'model': 'Land Cruiser Platinum',
                                    'year': 2025,
                                    'price': 25000,
                                    'original_price': 27000,
                                    'city': 'Baghdad',
                                    'status': 'active'
                                  }),
                                ])))))));
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(tester.takeException(), isNull);
        expect(find.text(package.priceText), findsOneWidget);
        expect(find.text(formatUsd(25000)), findsOneWidget);
        expect(find.text(formatIqd(32750000)), findsOneWidget);
        final primary = tester.widget<Text>(find.text(formatUsd(25000)));
        final secondary = tester.widget<Text>(find.text(formatIqd(32750000)));
        expect(
            primary.style!.fontSize!, greaterThan(secondary.style!.fontSize!));
        if (const bool.fromEnvironment('UI_CURRENCY_REVIEW_HOLD') &&
            locale == AppLocale.en &&
            dark) {
          debugPrint('UI_CURRENCY_REVIEW_READY');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 20)));
        }
        await tester.ensureVisible(find.text(formatUsd(25000)));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
