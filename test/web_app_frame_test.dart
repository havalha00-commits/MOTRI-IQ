import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/ui/web_app_frame.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('web frame reports its actual width at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Size? mediaSize;
      await tester.pumpWidget(MaterialApp(
        home: WebAppFrame(
          child: Builder(builder: (context) {
            mediaSize = MediaQuery.sizeOf(context);
            return const SizedBox.expand(key: ValueKey('content'));
          }),
        ),
      ));
      final expected = width > 600 ? 600.0 : width;
      expect(tester.getSize(find.byKey(const ValueKey('content'))).width, expected);
      expect(mediaSize, Size(expected, 900));
      expect(tester.takeException(), isNull);
    });
  }
}
