import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A one-finger page drag yields to pinch zoom as soon as a second finger lands.
class _PhotoPageDrag extends HorizontalDragGestureRecognizer {
  final _pointers = <int>{};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pointers.add(event.pointer);
    super.addAllowedPointer(event);
    if (_pointers.length > 1) resolve(GestureDisposition.rejected);
  }

  @override
  void handleEvent(PointerEvent event) {
    super.handleEvent(event);
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
    }
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _pointers.clear();
    super.didStopTrackingLastPointer(pointer);
  }
}

/// Owns paging and zoom state for the lifetime of the photo dialog.
class PhotoGallery extends StatefulWidget {
  const PhotoGallery(
      {super.key,
      required this.count,
      required this.itemBuilder,
      required this.hint,
      required this.resetZoomLabel,
      this.initialIndex = 0});
  final int count, initialIndex;
  final IndexedWidgetBuilder itemBuilder;
  final String hint, resetZoomLabel;
  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  late final PageController _controller;
  late int _selected;
  final _transform = TransformationController();
  bool _zoomed = false;
  Drag? _pageDrag;

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  void initState() {
    super.initState();
    _selected =
        widget.count > 0 ? widget.initialIndex.clamp(0, widget.count - 1) : 0;
    _controller = PageController(initialPage: _selected);
    _transform.addListener(_onTransform);
  }

  void _goTo(int index) {
    _transform.value = Matrix4.identity();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
    } else {
      _controller.animateToPage(index,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  @override
  void dispose() {
    _pageDrag?.cancel();
    _controller.dispose();
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MaterialLocalizations.of(context);
    return Dialog.fullscreen(
        child: SafeArea(
            child: Column(children: [
      Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 4, 4),
          child: Row(children: [
            Expanded(
                child: Semantics(
                    liveRegion: true,
                    child: Text(
                      widget.count == 0
                          ? '0 / 0'
                          : '${_selected + 1} / ${widget.count}',
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ))),
            if (_zoomed)
              IconButton(
                  tooltip: widget.resetZoomLabel,
                  icon: const Icon(Icons.fit_screen_rounded),
                  onPressed: () => _transform.value = Matrix4.identity()),
            if (widget.count > 1) ...[
              IconButton(
                  tooltip: labels.previousPageTooltip,
                  icon: const Icon(Icons.chevron_left_rounded),
                  onPressed: _selected > 0 ? () => _goTo(_selected - 1) : null),
              IconButton(
                  tooltip: labels.nextPageTooltip,
                  icon: const Icon(Icons.chevron_right_rounded),
                  onPressed: _selected < widget.count - 1
                      ? () => _goTo(_selected + 1)
                      : null),
            ],
            const CloseButton(),
          ])),
      Expanded(
          child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 4,
        child: RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          gestures: _zoomed
              ? const {}
              : <Type, GestureRecognizerFactory>{
                  _PhotoPageDrag:
                      GestureRecognizerFactoryWithHandlers<_PhotoPageDrag>(
                    _PhotoPageDrag.new,
                    (recognizer) {
                      recognizer.onStart = (details) {
                        _pageDrag = _controller.position
                            .drag(details, () => _pageDrag = null);
                      };
                      recognizer.onUpdate = (details) {
                        _pageDrag?.update(details);
                      };
                      recognizer.onEnd = (details) {
                        _pageDrag?.end(details);
                        _pageDrag = null;
                      };
                      recognizer.onCancel = () {
                        _pageDrag?.cancel();
                        _pageDrag = null;
                      };
                    },
                  ),
                },
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PageView.builder(
              controller: _controller,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.count,
              onPageChanged: (index) => setState(() => _selected = index),
              itemBuilder: (context, index) =>
                  Center(child: widget.itemBuilder(context, index)),
            ),
          ),
        ),
      )),
      Padding(
          padding: const EdgeInsets.all(16),
          child: Text(widget.hint,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall)),
    ])));
  }
}
