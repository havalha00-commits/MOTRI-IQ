import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import 'form_section.dart';
import 'content_direction.dart';

/// Input controllers live with the dialog route, including its closing animation.
class CarRequestEditorDialog extends StatefulWidget {
  const CarRequestEditorDialog(
      {super.key, required this.onSubmit, this.offer = false, this.errorKey});
  final bool offer;
  final Future<void> Function(Map<String, dynamic>) onSubmit;
  final String Function(Object)? errorKey;
  @override
  State<CarRequestEditorDialog> createState() => _CarRequestEditorDialogState();
}

class _CarRequestEditorDialogState extends State<CarRequestEditorDialog> {
  final _fields = <String, TextEditingController>{};
  bool _saving = false;
  String? _errorKey;
  TextEditingController _controller(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _controller(key).text.trim();
  String? _optional(String key) => _text(key).isEmpty ? null : _text(key);

  Future<void> _submit() async {
    if (_saving) return;
    final amount = parseFormDecimal(_text('price'));
    final name = _text('name');
    if (name.isEmpty || amount == null || amount <= 0) {
      setState(() {
        _errorKey =
            widget.offer ? 'req_type_and_price' : 'req_write_brand_budget';
      });
      return;
    }
    final from = parseFormInteger(_text('from')),
        to = parseFormInteger(_text('to'));
    if (!widget.offer &&
        [('from', from), ('to', to)].any((entry) =>
            _text(entry.$1).isNotEmpty &&
            (entry.$2 == null || entry.$2! < 1950 || entry.$2! > 2100))) {
      setState(() {
        _errorKey = 'ui_request_year_invalid';
      });
      return;
    }
    if (!widget.offer && from != null && to != null && from > to) {
      setState(() {
        _errorKey = 'req_year_range_hint';
      });
      return;
    }
    final payload = widget.offer
        ? <String, dynamic>{
            'vehicle': name,
            'offer_price': amount,
            'message': _optional('details')
          }
        : <String, dynamic>{
            'brand': name,
            'model': _optional('model'),
            'year_from': from,
            'year_to': to,
            'max_price': amount,
            'province': _optional('province'),
            'details': _optional('details')
          };
    setState(() {
      _saving = true;
      _errorKey = null;
    });
    try {
      await widget.onSubmit(payload);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorKey = widget.errorKey?.call(error) ??
              (widget.offer ? 'ui_request_offer_failed' : 'req_publish_failed');
        });
      }
    }
  }

  Widget _field(String key, String label,
          {bool numeric = false, int lines = 1}) =>
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
                  controller: _controller(key),
                  builder: (context, direction) => TextField(
                        key: ValueKey('request_$key'),
                        controller: _controller(key),
                        enabled: !_saving,
                        maxLines: lines,
                        textDirection: numeric ? TextDirection.ltr : direction,
                        keyboardType: numeric
                            ? const TextInputType.numberWithOptions(
                                decimal: true)
                            : lines > 1
                                ? TextInputType.multiline
                                : TextInputType.text,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontSize: 14),
                        decoration: const InputDecoration(),
                      ))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: appLocale.direction,
            child: AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              scrollable: true,
              title: Text(
                  t(widget.offer ? 'req_send_your_offer' : 'misc_request_cta'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
              content: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    _field(
                        'name',
                        widget.offer
                            ? 'req_car_available'
                            : 'req_brand_wanted'),
                    if (!widget.offer) ...[
                      _field('model', 'req_model_optional'),
                      _field('from', 'req_from_year', numeric: true),
                      _field('to', 'req_to_year', numeric: true),
                    ],
                    _field('price',
                        widget.offer ? 'req_budget_usd' : 'req_max_budget',
                        numeric: true),
                    if (!widget.offer)
                      _field('province', 'field_province_optional'),
                    _field(
                        'details',
                        widget.offer
                            ? 'field_optional_buyer_msg'
                            : 'field_extra_details',
                        lines: 3),
                  ])),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorKey != null)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Text(t(_errorKey!),
                                        style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error)))),
                          if (_saving)
                            const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: LinearProgressIndicator()),
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
                                    child: Text(t(widget.offer
                                        ? 'req_send_offer'
                                        : 'req_publish'))),
                              ]),
                        ]))
              ],
            )));
  }
}
