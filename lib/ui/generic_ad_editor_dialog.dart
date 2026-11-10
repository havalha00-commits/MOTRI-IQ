import 'dart:math';
import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import '../main.dart' show backendApi, backendAuthSession;
import '../market_images.dart';
import '../search/job_types.dart';
import 'form_section.dart';
import 'content_direction.dart';
import 'ugc_policy_consent.dart';

String _draftId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class GenericAdEditorDialog extends StatefulWidget {
  const GenericAdEditorDialog({super.key, required this.isMarket});
  final bool isMarket;
  @override
  State<GenericAdEditorDialog> createState() => _GenericAdEditorDialogState();
}

class _GenericAdEditorDialogState extends State<GenericAdEditorDialog> {
  final _title = TextEditingController(),
      _description = TextEditingController(),
      _city = TextEditingController(),
      _price = TextEditingController();
  final _images = <MarketImageEntry>[];
  final _id = _draftId();
  String? get _currentUserId => backendAuthSession.user?.id;
  late final String? _ownerId = _currentUserId;
  late final _uploadSession = ListingImageUploadSession(
      userId: _ownerId ?? '', isActive: () => mounted);
  String? _jobType, _error;
  bool _saving = false;
  @override
  void dispose() {
    for (final c in [_title, _description, _city, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final userId = _currentUserId;
    String? error;
    final price = parseFormDecimal(_price.text);
    if (userId == null || userId != _ownerId) {
      error = 'misc_login_first_publish';
    } else if (_title.text.trim().isEmpty) {
      error = widget.isMarket
          ? 'field_write_product_name'
          : 'field_write_job_title';
    } else if ((!widget.isMarket || _price.text.trim().isNotEmpty) &&
        (price == null || price < 0)) {
      error = widget.isMarket ? 'ui_invalid_price' : 'ui_invalid_salary';
    } else if (!widget.isMarket && _city.text.trim().isEmpty) {
      error = 'field_write_location';
    } else if (!widget.isMarket && _jobType == null) {
      error = 'job_pick_shift';
    } else if (widget.isMarket &&
        (_images.length < kMarketMinImages ||
            _images.length > kMarketMaxImages)) {
      error = 'ui_market_photo_limit';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    if (!widget.isMarket && _images.length > kJobMaxImages) {
      setState(() => _error = 'ui_job_photo_limit');
      return;
    }
    final entries = List<MarketImageEntry>.of(_images);
    final payload = <String, dynamic>{
      'id': _id,
      'user_id': userId!,
      'title': _title.text.trim(),
      'description':
          _description.text.trim().isEmpty ? null : _description.text.trim(),
      widget.isMarket ? 'price' : 'salary': price,
      if (!widget.isMarket) 'governorate': _city.text.trim(),
      if (!widget.isMarket) 'job_type': JobTypes.stored(_jobType!),
    };
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    var mediaReady = false;
    var checkingPolicy = true;
    try {
      if (!await ensureUgcPolicyAccepted(context, null, backendApi)) return;
      checkingPolicy = false;
      if (entries.isNotEmpty) {
        final urls = await (widget.isMarket
            ? resolveMarketImageUrls(
                userId: userId, entries: entries, session: _uploadSession)
            : resolveJobImageUrls(
                userId: userId, entries: entries, session: _uploadSession));
        if (urls.length != entries.length) {
          throw StateError('incomplete upload');
        }
        payload['images'] = urls;
      }
      mediaReady = true;
      if (!mounted) return;
      if (_currentUserId != userId) {
        throw StateError('session changed');
      }
      final response = await backendApi.post(
        'market/${widget.isMarket ? 'items' : 'jobs'}',
        body: payload,
      );
      if (response is! Map ||
          response['data'] is! Map ||
          response['data']['id']?.toString() != _id ||
          _currentUserId != userId) {
        throw StateError('unacknowledged insert');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = checkingPolicy
            ? 'ugc_policy_acceptance_failed'
            : _currentUserId != _ownerId
                ? 'ui_business_session_changed'
                : mediaReady
                    ? 'ui_ad_publish_failed'
                    : 'ui_car_upload_failed');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(TextEditingController controller, String key, String label,
          {int lines = 1, bool numeric = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ExcludeSemantics(
                child: Text(t(label),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(fontSize: 13))),
            const SizedBox(height: 6),
            Semantics(
                label: t(label),
                child: ContentDirectionBuilder(
                    controller: controller,
                    builder: (context, direction) => TextField(
                          key: ValueKey('generic_$key'),
                          controller: controller,
                          enabled: !_saving,
                          maxLines: lines,
                          maxLength: lines > 1 ? 2000 : null,
                          textDirection:
                              numeric ? TextDirection.ltr : direction,
                          keyboardType: numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true)
                              : lines > 1
                                  ? TextInputType.multiline
                                  : TextInputType.text,
                          textInputAction: lines > 1
                              ? TextInputAction.newline
                              : TextInputAction.next,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontSize: 14),
                          decoration: const InputDecoration(counterText: ''),
                        ))),
          ]));
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: appLocale.direction,
            child: AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              scrollable: true,
              title: Text(t(widget.isMarket ? 'market_add_product' : 'job_add'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
              content: SizedBox(
                  width: 520,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _field(
                            _title,
                            'title',
                            widget.isMarket
                                ? 'field_product_name'
                                : 'field_job_title'),
                        _field(
                            _price,
                            'price',
                            widget.isMarket
                                ? 'req_price_in_usd'
                                : 'field_salary',
                            numeric: true),
                        if (!widget.isMarket) ...[
                          _field(_city, 'city', 'field_location'),
                          Text(t('job_shift_type'),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                              key: const ValueKey('generic_shift'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 14),
                              initialValue: _jobType,
                              isExpanded: true,
                              items: [
                                for (final key in JobTypes.keys)
                                  DropdownMenuItem(
                                      value: key, child: Text(t(key)))
                              ],
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _jobType = v)),
                          const SizedBox(height: 16),
                        ],
                        _field(_description, 'description', 'field_desc',
                            lines: 3),
                        const Divider(height: 24),
                        if (widget.isMarket)
                          MarketImagesPicker(images: _images, enabled: !_saving)
                        else
                          JobImagesPicker(images: _images, enabled: !_saving),
                        if (_saving)
                          const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: LinearProgressIndicator()),
                      ])),
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
                                        style:
                                            TextStyle(color: scheme.error)))),
                          Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                    onPressed: _saving
                                        ? null
                                        : () => Navigator.pop(context, false),
                                    child: Text(t('common_cancel'))),
                                FilledButton(
                                    onPressed: _saving ? null : _submit,
                                    child: Text(t('account_publish'))),
                              ]),
                        ]))
              ],
            )));
  }
}
