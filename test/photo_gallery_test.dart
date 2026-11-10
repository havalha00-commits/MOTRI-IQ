import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/ui/photo_gallery.dart';
import 'package:motri_iq/main.dart' show buildAppTheme;

void main() {
  for (final direction in TextDirection.values) {
    for (final brightness in Brightness.values) {
      testWidgets('gallery preserves swiped page $direction $brightness',
          (tester) async {
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.physicalSize = const Size(320, 480);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        late StateSetter rebuild;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: StatefulBuilder(builder: (context, setState) {
            rebuild = setState;
            return Directionality(
                textDirection: direction,
                child: MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.8)),
                  child: PhotoGallery(
                    count: 3,
                    initialIndex: 1,
                    hint: 'Swipe to explore photos',
                    resetZoomLabel: 'Reset zoom',
                    itemBuilder: (_, i) => SizedBox.expand(
                        key: ValueKey('photo-$i'), child: Text('Photo $i')),
                  ),
                ));
          }),
        ));
        expect(find.text('2 / 3'), findsOneWidget);
        final bounds = tester.getRect(find.byType(PageView));
        await tester.dragFrom(
          Offset(bounds.left + bounds.width * .85, bounds.center.dy),
          Offset(-bounds.width * .7, 0),
        );
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pumpAndSettle();
        final afterSwipe = tester.widget<PageView>(find.byType(PageView));
        debugPrint(
            'GALLERY_SWIPE width=${bounds.width} page=${afterSwipe.controller!.page}');
        expect(find.text('3 / 3'), findsOneWidget);
        rebuild(() {});
        await tester.pumpAndSettle();
        expect(find.text('3 / 3'), findsOneWidget);
        final page = tester.widget<PageView>(find.byType(PageView));
        expect(page.controller!.page, closeTo(2, 0.01));
        expect(find.byType(CloseButton), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('gallery closes its dialog and clamps initial index',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => PhotoGallery(
                              count: 1,
                              initialIndex: 8,
                              hint: 'Photos',
                              resetZoomLabel: 'Reset zoom',
                              itemBuilder: (_, i) =>
                                  const Text('Single photo'))),
                      child: const Text('Open')),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 1'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.byType(PhotoGallery), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final horizontal in [false, true]) {
    testWidgets(
        'gallery pinches to zoom and pans without turning the page horizontal=$horizontal',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: PhotoGallery(
              count: 3,
              initialIndex: 1,
              hint: 'Photos',
              resetZoomLabel: 'Reset zoom',
              itemBuilder: (_, i) =>
                  SizedBox.expand(child: Text('Photo $i')))));
      await tester.pumpAndSettle();
      final center = tester.getCenter(find.byType(InteractiveViewer));
      final first = await tester.createGesture(pointer: 1);
      final second = await tester.createGesture(pointer: 2);
      await first.down(center - const Offset(50, 0));
      await second.down(center + const Offset(50, 0));
      final spread = horizontal ? const Offset(150, 0) : const Offset(50, 100);
      await first.moveTo(center - spread);
      await second.moveTo(center + spread);
      await tester.pump();
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      final viewer =
          tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(),
          greaterThan(1.1));
      expect(find.byTooltip('Reset zoom'), findsOneWidget);
      await tester.drag(find.byType(InteractiveViewer), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Reset zoom'));
      await tester.pump();
      expect(viewer.transformationController!.value.getMaxScaleOnAxis(), 1);
      expect(find.byTooltip('Reset zoom'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final direction in TextDirection.values) {
    testWidgets('gallery explicit navigation works $direction', (tester) async {
      if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
        tester.view.physicalSize = const Size(320, 320);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
      }
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2), disableAnimations: true),
            child: child!),
        home: Directionality(
            textDirection: direction,
            child: PhotoGallery(
                count: 3,
                hint: 'Photos',
                resetZoomLabel: 'Reset zoom',
                itemBuilder: (_, i) => Text('Photo $i'))),
      ));
      await tester.pumpAndSettle();
      final labels =
          MaterialLocalizations.of(tester.element(find.byType(PhotoGallery)));
      final previous = find.byTooltip(labels.previousPageTooltip);
      final next = find.byTooltip(labels.nextPageTooltip);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton &&
                  widget.tooltip == labels.previousPageTooltip))
              .onPressed,
          isNull);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expect(
          tester
              .widget<IconButton>(find.byWidgetPredicate((widget) =>
                  widget is IconButton &&
                  widget.tooltip == labels.nextPageTooltip))
              .onPressed,
          isNull);
      await tester.tap(previous);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      if (const bool.fromEnvironment('UI_CURRENT_TYPOGRAPHY_HOLD')) {
        debugPrint('TYPOGRAPHY_GALLERY_${direction.name.toUpperCase()}');
        await tester
            .runAsync(() => Future<void>.delayed(const Duration(seconds: 12)));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
