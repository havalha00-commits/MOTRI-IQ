// Read-only probe for the seller verified badge: it must appear next to the
// seller name on CarDetailsPage, only when the seller is verified, stay
// icon-only, keep RTL spacing, and never overflow long seller names.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:motri_iq/main.dart';

const Map<String, Size> phones = <String, Size>{
  'se_320x568': Size(320, 568),
  'budget_360x640': Size(360, 640),
  'promax_430x932': Size(430, 932),
};

Widget host(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void sizeTo(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  });

  for (final p in phones.entries) {
    testWidgets('tick appears only when verified — ${p.key}', (tester) async {
      sizeTo(tester, p.value);

      // Verified seller: the icon shows.
      await tester.pumpWidget(host(Row(children: <Widget>[
        const Flexible(
            child: Text('معرض Baghdad Auto',
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        SellerVerifiedTick(sellerId: 'seller-1', future: Future<bool>.value(true)),
      ])));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget,
          reason: 'verified tick missing at ${p.key}');
      expect(tester.takeException(), isNull);

      // Unverified seller: nothing renders.
      await tester.pumpWidget(host(Row(children: <Widget>[
        const Flexible(
            child: Text('معرض Baghdad Auto',
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        SellerVerifiedTick(
            sellerId: 'seller-2', future: Future<bool>.value(false)),
      ])));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byIcon(Icons.verified_rounded), findsNothing,
          reason: 'tick must not show for unverified at ${p.key}');
      expect(tester.takeException(), isNull);

      // Still loading: no layout jump, no exception.
      await tester.pumpWidget(host(Row(children: <Widget>[
        const Flexible(
            child: Text('معرض Baghdad Auto',
                maxLines: 1, overflow: TextOverflow.ellipsis)),
        SellerVerifiedTick(
            sellerId: 'seller-3', future: Completer<bool>().future),
      ])));
      await tester.pump();
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('long seller name ellipsizes, badge stays — no overflow',
      (tester) async {
    sizeTo(tester, const Size(320, 568));
    await tester.pumpWidget(host(Row(children: <Widget>[
      const Flexible(
        child: Text(
          'معرض Baghdad Auto Showroom For Everything And Anything',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      SellerVerifiedTick(
          sellerId: 'seller-4', future: Future<bool>.value(true)),
    ])));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the fetch helper is safe on empty id and errors', (test) async {
    expect(await fetchSellerVerified(null), isFalse);
    expect(await fetchSellerVerified(''), isFalse);
    expect(await fetchSellerVerified('   '), isFalse);
  });
}