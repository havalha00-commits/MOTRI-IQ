import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'l10n/app_delegates.dart';
import 'l10n/app_locale.dart';
import 'main.dart';
import 'design/app_icons.dart';
import 'ui/form_section.dart';
import 'ui/account_feed_state.dart';
import 'ui/account_scoped_view.dart';
import 'ui/photo_gallery.dart';
import 'ui/content_direction.dart';
import 'search/job_types.dart';

const int kMarketMinImages = 2;

const int kMarketMaxImages = 6;

List<String> marketItemImageUrls(Map<String, dynamic> item) {
  final raw = item['images'];
  if (raw == null) return [];
  return _normalizeImageValue(raw);
}

String _resolveBackendUrl(String path) {
  final uri = Uri.tryParse(path);
  if (uri != null && uri.hasScheme && uri.host.isNotEmpty) return path;
  final base = backendUrl.replaceAll(RegExp(r'/$'), '');
  if (path.startsWith('/')) return '$base$path';
  return '$base/$path';
}

List<String> _normalizeImageValue(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) return raw.expand(_normalizeImageValue).toSet().toList();
  final value = raw.toString().trim();
  if (value.startsWith('[')) {
    try {
      return _normalizeImageValue(jsonDecode(value));
    } catch (_) {
      return [];
    }
  }
  final uri = Uri.tryParse(value);
  if (uri == null) return [];
  if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) {
    return [value];
  }
  // G10.52 M1C: backend-controlled market delivery URLs are renderable by Flutter.
  if (value.startsWith('/api/market/images/')) return [_resolveBackendUrl(value)];
  if (uri.path.startsWith('/api/market/images/')) return [_resolveBackendUrl(value)];
  return [];
}

class MarketImageEntry {
  final String? url;

  final XFile? file;

  const MarketImageEntry.url(this.url) : file = null;
  const MarketImageEntry.file(this.file) : url = null;

  bool get isNew => file != null;
}

/// One session per editor: completed photos and retry paths survive failures.
class ListingImageUploadSession {
  ListingImageUploadSession({required this.userId, required this.isActive});
  final String userId;
  final bool Function() isActive;
  final _completed = <XFile, String>{};

  void _checkActive() {
    if (!isActive() || backendAuthSession.user?.id != userId) {
      throw StateError('inactive photo editor');
    }
  }

  Future<List<String>> resolve(List<MarketImageEntry> entries,
      {required bool jobs}) async {
    final urls = <String>[];
    for (final entry in entries) {
      _checkActive();
      if (!entry.isNew) {
        urls.add(entry.url!);
        continue;
      }
      final file = entry.file!;
      if (!_completed.containsKey(file)) {
        final bytes = await file.readAsBytes();
        _checkActive();
        final originalExt = file.name.split('.').last.toLowerCase();
        final isPng = bytes.length >= 8 &&
            bytes[0] == 137 &&
            bytes[1] == 80 &&
            bytes[2] == 78 &&
            bytes[3] == 71;
        final isJpeg = bytes.length >= 3 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255;
        final isWebp = bytes.length >= 12 &&
            String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
            String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
        final ext = isPng
            ? 'png'
            : isJpeg
                ? 'jpg'
                : isWebp
                    ? 'webp'
                    : ['jpg', 'jpeg', 'png', 'webp'].contains(originalExt)
                        ? originalExt
                        : 'jpg';
        // G10.52 M1C: market/job uploads use authenticated server-owned refs (no public_url, no arbitrary bucket/path).
        final kind = jobs ? 'job' : 'market';
        final response = await backendApi
            .putBytes(
              'market/uploads',
              query: {'kind': kind},
              body: bytes,
              contentType: ext == 'jpg' || ext == 'jpeg'
                  ? 'image/jpeg'
                  : 'image/$ext',
              backendOnly: kMotriLocalTest,
            )
            .timeout(const Duration(seconds: 30));
        final data = response is Map ? response['data'] : null;
        final ref = data is Map ? data['delivery_url'] ?? data['ref'] : null;
        if (ref is! String || ref.trim().isEmpty) {
          throw StateError('Image upload acknowledgement missing');
        }
        _completed[file] = ref.trim();
        _checkActive();
      }
      urls.add(_completed[file]!);
    }
    _checkActive();
    return urls;
  }
}

Future<List<String>> resolveMarketImageUrls({
  required String userId,
  required List<MarketImageEntry> entries,
  ListingImageUploadSession? session,
}) =>
    (session ?? ListingImageUploadSession(userId: userId, isActive: () => true))
        .resolve(entries, jobs: false);

Future<List<String>> uploadMarketImages({
  required String userId,
  required List<XFile> images,
}) =>
    resolveMarketImageUrls(
        userId: userId, entries: images.map(MarketImageEntry.file).toList());

const int kJobMaxImages = 5;

Future<List<String>> resolveJobImageUrls({
  required String userId,
  required List<MarketImageEntry> entries,
  ListingImageUploadSession? session,
}) =>
    (session ?? ListingImageUploadSession(userId: userId, isActive: () => true))
        .resolve(entries, jobs: true);

/// Both creation surfaces share the same accessible, theme-aware photo editor.
class JobImagesPicker extends StatelessWidget {
  const JobImagesPicker({super.key, required this.images, this.enabled = true});
  final List<MarketImageEntry> images;
  final bool enabled;
  @override
  Widget build(BuildContext context) =>
      _ListingImagesPicker(images: images, enabled: enabled, jobs: true);
}

class MarketImagesPicker extends StatelessWidget {
  const MarketImagesPicker(
      {super.key, required this.images, this.enabled = true});
  final List<MarketImageEntry> images;
  final bool enabled;
  @override
  Widget build(BuildContext context) =>
      _ListingImagesPicker(images: images, enabled: enabled, jobs: false);
}

class _ListingImagesPicker extends StatefulWidget {
  const _ListingImagesPicker(
      {required this.images, required this.enabled, required this.jobs});
  final List<MarketImageEntry> images;
  final bool enabled, jobs;
  @override
  State<_ListingImagesPicker> createState() => _ListingImagesPickerState();
}

class _ListingImagesPickerState extends State<_ListingImagesPicker> {
  bool _picking = false;
  int get _max => widget.jobs ? kJobMaxImages : kMarketMaxImages;
  bool get _enabled => widget.enabled && !_picking;
  Future<void> _pick() async {
    if (!_enabled || widget.images.length >= _max) return;
    setState(() => _picking = true);
    try {
      final picked = await ImagePicker().pickMultiImage();
      if (!mounted || !widget.enabled) return;
      setState(() => widget.images.addAll(
          picked.take(_max - widget.images.length).map(MarketImageEntry.file)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('market_gallery_error'))));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _main(int index) {
    if (!_enabled || index == 0) return;
    setState(() => widget.images.insert(0, widget.images.removeAt(index)));
  }

  void _move(int from, int to) {
    if (!_enabled || from == to || from >= widget.images.length) return;
    setState(() => widget.images.insert(to, widget.images.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    final maxed = widget.images.length >= _max;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Text(
                t(widget.jobs ? 'market_job_images' : 'market_product_images'),
                style: Theme.of(context).textTheme.titleSmall)),
        const SizedBox(width: 8),
        Text('${widget.images.length} / $_max',
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.bodySmall),
      ]),
      const SizedBox(height: 6),
      Text(t(widget.jobs ? 'ui_job_photo_limit' : 'ui_market_photo_limit'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant)),
      const SizedBox(height: 12),
      OutlinedButton.icon(
          onPressed: _enabled && !maxed ? _pick : null,
          icon: _picking
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(AppIcons.addPhoto),
          label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(t(maxed ? 'img_reached_max' : 'market_add_images')))),
      if (widget.images.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < widget.images.length; i++)
            DragTarget<int>(
                onWillAcceptWithDetails: (d) => _enabled && d.data != i,
                onAcceptWithDetails: (d) => _move(d.data, i),
                builder: (context, candidate, rejected) => LongPressDraggable<
                        int>(
                    data: i,
                    maxSimultaneousDrags: _enabled ? 1 : 0,
                    feedback: Material(
                        child: SizedBox(
                            width: 112,
                            height: 112,
                            child: _EntryPreview(entry: widget.images[i]))),
                    childWhenDragging: const SizedBox(width: 112, height: 112),
                    child: SizedBox(
                        width: 112,
                        height: 112,
                        child: Material(
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: i == 0 && !widget.jobs ||
                                          candidate.isNotEmpty
                                      ? scheme.primary
                                      : scheme.outlineVariant,
                                  width: 2)),
                          child: Stack(fit: StackFit.expand, children: [
                            InkWell(
                                onTap: _enabled && !widget.jobs
                                    ? () => _main(i)
                                    : null,
                                child: Semantics(
                                    label:
                                        '${i + 1}: ${t('ui_make_main_photo')}',
                                    child: _EntryPreview(
                                        entry: widget.images[i]))),
                            PositionedDirectional(
                                top: 0,
                                end: 0,
                                child: IconButton(
                                    tooltip: t('car_delete_image'),
                                    onPressed: _enabled
                                        ? () => setState(
                                            () => widget.images.removeAt(i))
                                        : null,
                                    style: IconButton.styleFrom(
                                        backgroundColor: scheme.surface,
                                        minimumSize: const Size(44, 44)),
                                    icon:
                                        const Icon(AppIcons.close, size: 18))),
                            if (i == 0 && !widget.jobs)
                              Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: IgnorePointer(
                                      child: ColoredBox(
                                          color: scheme.primary,
                                          child: Padding(
                                              padding: const EdgeInsets.all(3),
                                              child: Text(
                                                  t('common_main_image'),
                                                  textAlign: TextAlign.center,
                                                  maxLines: 2,
                                                  style: TextStyle(
                                                      fontSize: 9,
                                                      color: scheme
                                                          .onPrimary)))))),
                          ]),
                        )))),
        ]),
        if (!widget.jobs)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('car_reorder_images'),
                  style: Theme.of(context).textTheme.bodySmall)),
      ],
    ]);
  }
}

class _EntryPreview extends StatefulWidget {
  const _EntryPreview({required this.entry});
  final MarketImageEntry entry;
  @override
  State<_EntryPreview> createState() => _EntryPreviewState();
}

class _EntryPreviewState extends State<_EntryPreview> {
  late var _bytes = widget.entry.file?.readAsBytes();
  @override
  void didUpdateWidget(covariant _EntryPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.file != widget.entry.file) {
      _bytes = widget.entry.file?.readAsBytes();
    }
  }

  Widget _error() => Center(
      child: Icon(AppIcons.imageUnavailable,
          color: Theme.of(context).colorScheme.onSurfaceVariant));
  @override
  Widget build(BuildContext context) {
    if (widget.entry.url != null) {
      return Image.network(widget.entry.url!,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => _error());
    }
    return FutureBuilder(
        future: _bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) return _error();
          if (!snapshot.hasData) {
            return const Center(
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2)));
          }
          return Image.memory(snapshot.data!,
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => _error());
        });
  }
}

class MarketItemGallery extends StatefulWidget {
  const MarketItemGallery({super.key, required this.urls, this.height = 260});
  final List<String> urls;
  final double height;
  @override
  State<MarketItemGallery> createState() => _MarketItemGalleryState();
}

class _MarketItemGalleryState extends State<MarketItemGallery> {
  final _controller = PageController();
  int _index = 0;
  @override
  void didUpdateWidget(covariant MarketItemGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_index >= widget.urls.length) {
      _index = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int index) {
    if (!_controller.hasClients || index < 0 || index >= widget.urls.length) {
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(index);
    } else {
      _controller.animateToPage(index,
          duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _fullscreen(int index) => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) => PhotoGallery(
          count: widget.urls.length,
          initialIndex: index,
          hint: t('car_swipe'),
          resetZoomLabel: t('ui_reset_zoom'),
          itemBuilder: (context, i) => Image.network(widget.urls[i],
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(AppIcons.imageUnavailable,
                  color: Theme.of(context).colorScheme.onSurfaceVariant))));
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    final labels = MaterialLocalizations.of(context);
    if (widget.urls.isEmpty) {
      return SizedBox(
          height: widget.height,
          child: Center(
              child: Icon(AppIcons.imageUnavailable,
                  size: 40, color: scheme.onSurfaceVariant)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
              height: widget.height,
              child: Stack(fit: StackFit.expand, children: [
                PageView.builder(
                    controller: _controller,
                    itemCount: widget.urls.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) => InkWell(
                        onTap: () => _fullscreen(i),
                        child: Semantics(
                            button: true,
                            label:
                                '${t('ui_photo_count').replaceAll('{count}', '${i + 1}')} / ${widget.urls.length}',
                            child: CarPhoto(
                                urls: [widget.urls[i]],
                                radius: 0,
                                placeholderIcon: AppIcons.imageUnavailable)))),
                PositionedDirectional(
                    bottom: 10,
                    end: 10,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .7),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('${_index + 1} / ${widget.urls.length}',
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12)))),
                if (widget.urls.length > 1) ...[
                  PositionedDirectional(
                      start: 4,
                      top: widget.height / 2 - 24,
                      child: _arrow(
                          labels.previousPageTooltip,
                          Icons.chevron_left,
                          _index > 0 ? () => _go(_index - 1) : null)),
                  PositionedDirectional(
                      end: 4,
                      top: widget.height / 2 - 24,
                      child: _arrow(
                          labels.nextPageTooltip,
                          Icons.chevron_right,
                          _index < widget.urls.length - 1
                              ? () => _go(_index + 1)
                              : null)),
                ],
              ]))),
      if (widget.urls.length > 1)
        Padding(
            padding: const EdgeInsets.only(top: 10),
            child: SizedBox(
                height: 64,
                child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.urls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => Semantics(
                        selected: i == _index,
                        child: InkWell(
                            onTap: () => _go(i),
                            child: Container(
                                width: 76,
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: i == _index
                                            ? scheme.primary
                                            : scheme.outlineVariant,
                                        width: 2)),
                                child: CarPhoto(
                                    urls: [widget.urls[i]], radius: 7))))))),
    ]);
  }

  Widget _arrow(String label, IconData icon, VoidCallback? action) =>
      IconButton(
          tooltip: label,
          onPressed: action,
          style: IconButton.styleFrom(
              backgroundColor:
                  Colors.black.withValues(alpha: action == null ? .25 : .65),
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white54,
              minimumSize: const Size(48, 48)),
          icon: Icon(icon));
}

bool _isJob(Map<String, dynamic> item) =>
    item.containsKey('company') ||
    item.containsKey('salary') ||
    item.containsKey('job_type');
String _field(Map<String, dynamic> item, String key) {
  final value = item[key]?.toString().trim() ?? '';
  return value == 'null' ? '' : value;
}

class EditMarketImagesDialog extends StatefulWidget {
  const EditMarketImagesDialog({super.key, required this.item});
  final Map<String, dynamic> item;
  @override
  State<EditMarketImagesDialog> createState() => _EditMarketImagesDialogState();
}

class _EditMarketImagesDialogState extends State<EditMarketImagesDialog> {
  late final _entries = [
    for (final url in marketItemImageUrls(widget.item))
      MarketImageEntry.url(url)
  ];
  final _ownerId = backendAuthSession.user?.id;
  late final _uploadSession = ListingImageUploadSession(
      userId: _ownerId ?? '', isActive: () => mounted);
  bool _saving = false;
  String? _error;
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return PopScope(
        canPop: !_saving,
        child: AlertDialog(
          title: Text(t('market_edit_images_2'),
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_isJob(widget.item))
                  JobImagesPicker(images: _entries, enabled: !_saving)
                else
                  MarketImagesPicker(images: _entries, enabled: !_saving),
              ]))),
          actions: [
            SizedBox(
                width: double.infinity,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Semantics(
                                liveRegion: true,
                                child: Text(t(_error!),
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)))),
                      Wrap(
                          alignment: WrapAlignment.end,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                                onPressed: _saving
                                    ? null
                                    : () => Navigator.pop(context),
                                child: Text(t('common_cancel'))),
                            FilledButton(
                                onPressed: _saving ? null : _save,
                                child: _saving
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary))
                                    : Text(t('common_save')))
                          ]),
                    ]))
          ],
        ));
  }

  Future<void> _save() async {
    if (_saving) return;
    final user = backendAuthSession.user;
    if (user == null ||
        user.id != _ownerId ||
        user.id != widget.item['user_id']?.toString() ||
        _field(widget.item, 'id').isEmpty) {
      setState(() => _error = 'market_login_to_save');
      return;
    }
    final jobs = _isJob(widget.item);
    if ((!jobs && _entries.length < kMarketMinImages) ||
        _entries.length > (jobs ? kJobMaxImages : kMarketMaxImages)) {
      setState(
          () => _error = jobs ? 'ui_job_photo_limit' : 'ui_market_photo_limit');
      return;
    }
    final entries = List<MarketImageEntry>.of(_entries);
    setState(() {
      _saving = true;
      _error = null;
    });
    var mediaReady = false;
    try {
      final urls = await (jobs
          ? resolveJobImageUrls(
              userId: user.id, entries: entries, session: _uploadSession)
          : resolveMarketImageUrls(
              userId: user.id, entries: entries, session: _uploadSession));
      mediaReady = true;
      if (!mounted) return;
      if (backendAuthSession.user?.id != user.id) {
        throw StateError('session changed');
      }
      final response = await backendApi.patch(
        'market/${jobs ? 'jobs' : 'items'}/${widget.item['id']}/images',
        body: {'images': urls},
      );
      if (response is! Map ||
          response['data'] is! Map ||
          response['data']['id']?.toString() !=
              widget.item['id']?.toString() ||
          backendAuthSession.user?.id != user.id) {
        throw StateError('unacknowledged update');
      }
      if (!mounted) return;
      Navigator.pop(context, urls);
    } catch (_) {
      if (mounted) {
        setState(() => _error =             backendAuthSession.user?.id != _ownerId
            ? 'ui_business_session_changed'
            : mediaReady
                ? 'market_images_error'
                : 'ui_car_upload_failed');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class MarketItemDetailsPage extends StatefulWidget {
  const MarketItemDetailsPage(
      {super.key, required this.item, this.icon = AppIcons.market});
  final Map<String, dynamic> item;
  final IconData icon;
  @override
  State<MarketItemDetailsPage> createState() => _MarketItemDetailsPageState();
}

class _MarketItemDetailsPageState extends State<MarketItemDetailsPage>
    with AccountFeedState<MarketItemDetailsPage> {
  bool _isAdmin = false, _deleting = false, _editing = false;
  List<String>? _editedUrls;
  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void reloadAccountFeed() {
    _isAdmin = false;
    _deleting = false;
    _editing = false;
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    final user = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    final admin = await currentUserIsAdmin();
    if (accountMatches(user, epoch)) {
      setState(() => _isAdmin = admin);
    }
  }

  Future<void> _delete() async {
    final account = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (_deleting || !_isAdmin || account == null) return;
    setState(() => _deleting = true);
    try {
      final confirmed = await confirmAdminDeleteAd(context,
          itemTitle: widget.item['title']?.toString(),
          sectionKey: _isJob(widget.item) ? 'section_jobs' : 'section_market');
      if (confirmed != true ||
          !accountMatches(account, epoch)) {
        return;
      }
      final ok = await adminDeleteAd(
          _isJob(widget.item) ? 'jobs' : 'market_items',
          _field(widget.item, 'id'));
      if (!mounted || !accountMatches(account, epoch)) return;
      adminDeleteMessage(context, ok);
      if (ok) Navigator.of(context).pop();
    } finally {
      if (accountMatches(account, epoch)) setState(() => _deleting = false);
    }
  }

  Future<void> _deleteOwnMarketAd() async {
    final account = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    final id = _field(widget.item, 'id');
    if (_deleting ||
        account == null ||
        account != widget.item['user_id']?.toString() ||
        id.isEmpty) {
      return;
    }
    setState(() => _deleting = true);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('market_delete_ad')),
          content: Text(t('market_delete_ad_confirm')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('common_delete')),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          !accountMatches(account, epoch)) {
        return;
      }
      final response = await backendApi.delete('market/items/$id');
      if (!mounted || !accountMatches(account, epoch)) return;
      if (response is! Map ||
          response['success'] != true ||
          response['data'] is! Map ||
          response['data']['id']?.toString() != id ||
          backendAuthSession.user?.id != account) {
        throw StateError('Market ad deletion was not acknowledged');
      }
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('market_delete_ad_done'))));
      Navigator.of(context).pop();
    } catch (error) {
      debugPrint('market ad delete failed: ${error.runtimeType}');
      if (mounted && accountMatches(account, epoch)) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('market_delete_ad_failed'))));
      }
    } finally {
      if (mounted && accountMatches(account, epoch)) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _edit() async {
    final account = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (_editing || account == null) return;
    setState(() => _editing = true);
    final saved = await showDialog<List<String>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AccountScopedView(accountId: account, child: EditMarketImagesDialog(item: {
              ...widget.item,
              if (_editedUrls != null) 'images': _editedUrls
            })));
    if (!mounted || !accountMatches(account, epoch)) return;
    setState(() {
      _editing = false;
      if (saved != null) _editedUrls = saved;
    });
    if (saved != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('market_images_saved'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final theme = Theme.of(context), scheme = Theme.of(context).colorScheme;
    final item = widget.item, urls = _editedUrls ?? marketItemImageUrls(item);
    final title = [
      _field(item, 'title'),
      _field(item, 'name'),
      _field(item, 'product_name')
    ].firstWhere((v) => v.isNotEmpty, orElse: () => t('misc_default_ad'));
    final description = _field(item, 'description'),
        phone = _field(item, 'phone');
    final location = {
      _field(item, 'governorate'),
      _field(item, 'province'),
      _field(item, 'city')
    }.where((v) => v.isNotEmpty).join(' · ');
    final price = _field(item, 'price'), salary = _field(item, 'salary');
    final amount = parseFormDecimal(price);
    final asking = price.isEmpty
        ? salary
        : amount == null
            ? price
            : formatUsd(amount);
    final owner = backendAuthSession.user?.id != null &&
        backendAuthSession.user?.id == item['user_id']?.toString();
    return Scaffold(
        appBar: AppBar(title: Text(t('ad_details')), actions: [
          if (_isAdmin)
            IconButton(
                tooltip: t('admin_delete_ad'),
                onPressed: _deleting ? null : _delete,
                icon: Icon(AppIcons.delete, color: scheme.error)),
        ]),
        body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      if (urls.isNotEmpty)
                        LayoutBuilder(
                            builder: (_, size) => MarketItemGallery(
                                urls: urls,
                                height: (size.maxWidth * .75).clamp(180, 420)))
                      else
                        Container(
                            height: 160,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: scheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(16)),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(widget.icon,
                                      size: 36, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 8),
                                  Text(t('market_no_images_ad'),
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: scheme.onSurfaceVariant))
                                ])),
                      const SizedBox(height: 20),
                      Text(title,
                          textDirection: contentTextDirection(context, title),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      if (asking.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(asking,
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800))),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        if (_field(item, 'category').isNotEmpty)
                          _info(AppIcons.category, _field(item, 'category')),
                        if (location.isNotEmpty)
                          _info(AppIcons.location, location),
                        if (_field(item, 'job_type').isNotEmpty)
                          _info(AppIcons.work,
                              JobTypes.label(_field(item, 'job_type'))),
                      ]),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        Text(t('field_desc'),
                            style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(description,
                            textDirection:
                                contentTextDirection(context, description),
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(height: 1.6))
                      ],
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 24),
                        ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(AppIcons.call,
                                color: scheme.onSurfaceVariant),
                            title: SelectableText(phone,
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.titleMedium))
                      ],
                      if (owner) ...[
                        const SizedBox(height: 24),
                        FilledButton.icon(
                            onPressed: _editing ? null : _edit,
                            icon: const Icon(AppIcons.edit),
                            label: Text(t('market_edit_images_2'))),
                        if (!_isJob(item)) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                              onPressed: _deleting ? null : _deleteOwnMarketAd,
                              icon: Icon(AppIcons.delete, color: scheme.error),
                              label: Text(t('market_delete_ad'),
                                  style: TextStyle(color: scheme.error))),
                        ],
                      ],
                    ]))));
  }

  Widget _info(IconData icon, String label) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Flexible(
              child: Text(label,
                  textDirection: contentTextDirection(context, label),
                  style: Theme.of(context).textTheme.bodySmall))
        ]));
  }
}
