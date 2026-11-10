import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';

void main() {
  testWidgets(
      'small brand artwork fits at large RTL text and stops for reduced motion',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
            body: MediaQuery(
                data: const MediaQueryData(
                    textScaler: TextScaler.linear(2), disableAnimations: true),
                child: const Directionality(
                    textDirection: TextDirection.rtl,
                    child: Center(child: BrandLogo(size: 40)))))));
    final text = find.descendant(
        of: find.byType(BrandLogo), matching: find.byType(Text));
    expect(tester.getSize(text).height, lessThanOrEqualTo(40));
    expect(tester.widget<Text>(text).textScaler, TextScaler.noScaling);
    final marker = find
        .descendant(
            of: find.byType(BrandLogo), matching: find.byType(Positioned))
        .first;
    final before = tester.widget<Positioned>(marker).left;
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Positioned>(marker).left, before);
    expect(tester.takeException(), isNull);
  });
}
