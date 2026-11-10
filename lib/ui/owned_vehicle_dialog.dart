import 'package:flutter/material.dart';
import '../backend_api.dart';
import '../main.dart'
    show backendApi, backendAuthSession, iraqiProvinces, vehicleBodyTypes;
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import 'content_direction.dart';
import 'form_section.dart';

/// Owns the draft until the server acknowledges the scoped mutation.
class OwnedVehicleDialog extends StatefulWidget {
  const OwnedVehicleDialog({super.key, required this.car, this.delete = false});
  final Map<String, dynamic> car;
  final bool delete;
  @override
  State<OwnedVehicleDialog> createState() => _OwnedVehicleDialogState();
}

class _OwnedVehicleDialogState extends State<OwnedVehicleDialog> {
  String? get _currentUserId => backendAuthSession.user?.id;
  late final String? _owner = _currentUserId;
  late final _id = widget.car['id']?.toString();
  late final _fields = {
    for (final key in [
      'brand',
      'model',
      'year',
      'price',
      'city',
      'seller_phone',
      'description'
    ])
      key: TextEditingController(text: widget.car[key]?.toString() ?? '')
  };
  late String _province = widget.car['province']?.toString() ?? '';
  late String _body = widget.car['body_type']?.toString() ?? '';
  bool _saving = false;
  String? _error;
  String? _errorCode;
  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  String _text(String key) => _fields[key]!.text.trim();
  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final year = parseFormInteger(_text('year'));
    final price = parseFormDecimal(_text('price'));
    String? error;
    if (_owner == null ||
        _currentUserId != _owner ||
        _id == null ||
        _id.isEmpty ||
        widget.car['user_id']?.toString() != _owner) {
      error = 'misc_login_first_publish';
    } else if (!widget.delete) {
      if (_text('brand').isEmpty || _text('model').isEmpty) {
        error = 'wanted';
      } else if (_text('year').isNotEmpty &&
          (year == null || year < 1900 || year > DateTime.now().year + 1)) {
        error = 'ui_invalid_year';
      } else if (_text('price').isNotEmpty && (price == null || price < 0)) {
        error = 'ui_invalid_price';
      }
    }
    if (error != null) {
      setState(() {
        _error = error;
        _errorCode = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _errorCode = null;
    });
    try {
      final Map<String, dynamic>? updated;
      if (widget.delete) {
        final response = await backendApi.delete('cars/my/$_id');
        updated = response is Map && response['data'] is Map
            ? Map<String, dynamic>.from(response['data'] as Map)
            : null;
      } else {
        final response = await backendApi.patch(
          'cars/my/$_id',
          body: {
              'brand': _text('brand'),
              'model': _text('model'),
              'year': year,
              'price': price,
              for (final key in ['city', 'seller_phone', 'description'])
                key: _text(key).isEmpty ? null : _text(key),
              'province': _province.isEmpty ? null : _province,
              'body_type': _body.isEmpty ? null : _body,
          },
        );
        updated = response is Map && response['data'] is Map
            ? Map<String, dynamic>.from(response['data'] as Map)
            : null;
      }
      if (updated?['id']?.toString() != _id ||
          _currentUserId != _owner) {
        throw StateError('Mutation was not acknowledged for this listing');
      }
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context, true);
    } on BackendApiException catch (error) {
      debugPrint(
          'owned vehicle ${widget.delete ? 'delete' : 'update'} failed: ${error.statusCode ?? 'unknown status'}');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.delete
              ? 'ui_vehicle_delete_failed'
              : 'ui_vehicle_save_failed';
          _errorCode = error.statusCode?.toString();
        });
      }
    } catch (error) {
      debugPrint(
          'owned vehicle ${widget.delete ? 'delete' : 'update'} failed: ${error.runtimeType}');
      if (mounted) {
        setState(() {
          _saving = false;
          _error = widget.delete
              ? 'ui_vehicle_delete_failed'
              : 'ui_vehicle_save_failed';
          _errorCode = null;
        });
      }
    }
  }

  Widget _field(String key, String label,
      {TextInputType type = TextInputType.text, int lines = 1}) {
    Widget input(TextDirection direction) => Semantics(
        label: t(label),
        child: TextField(
            key: ValueKey('owned_$key'),
            controller: _fields[key],
            enabled: !_saving,
            keyboardType: type,
            textDirection: direction,
            textInputAction:
                lines > 1 ? TextInputAction.newline : TextInputAction.next,
            maxLines: lines,
            maxLength: lines > 1 ? 2000 : null,
            decoration: const InputDecoration(counterText: '')));
    final identifier = type.index == TextInputType.number.index ||
        type.index == TextInputType.phone.index;
    return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExcludeSemantics(
              child: Text(t(label),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(fontSize: 13, fontWeight: FontWeight.w600))),
          const SizedBox(height: 6),
          if (identifier)
            input(TextDirection.ltr)
          else
            ContentDirectionBuilder(
                controller: _fields[key]!,
                builder: (context, direction) => input(direction)),
        ]));
  }

  Widget _selector(String key, String label, String value, List<String> options,
          ValueChanged<String> change) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: DropdownButtonFormField<String>(
              key: ValueKey('owned_$key'),
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(label)),
              items: [
                DropdownMenuItem(
                    value: '', child: Text(t('common_unspecified'))),
                for (final option in {
                  ...options.where((v) => v.isNotEmpty),
                  if (value.isNotEmpty) value
                })
                  DropdownMenuItem(
                      value: option,
                      child: Text(option,
                          textDirection: contentTextDirection(context, option),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis))
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => change(value ?? ''))));
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    final message = _error == 'ui_invalid_year'
        ? t(_error!).replaceAll('{year}', '${DateTime.now().year + 1}')
        : _error == null
            ? null
            : [
                t(_error!),
                if (_errorCode != null)
                  '${t('ui_backend_error_code')}: $_errorCode',
              ].join('\n');
    return PopScope(
        canPop: !_saving,
        child: Directionality(
            textDirection: appLocale.direction,
            child: AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              scrollable: true,
              title: Text(
                  t(widget.delete
                      ? 'misc_delete_ad_confirm'
                      : 'account_edit_ads'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              content: SizedBox(
                  width: 520,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.delete)
                          Text(t('misc_deleted_gone'))
                        else ...[
                          _field('brand', 'field_brand'),
                          _field('model', 'field_model'),
                          _field('year', 'field_year',
                              type: TextInputType.number),
                          _field('price', 'req_price_in_usd',
                              type: const TextInputType.numberWithOptions(
                                  decimal: true)),
                          _selector('province', 'field_province', _province,
                              iraqiProvinces, (v) => _province = v),
                          _field('city', 'field_city'),
                          _selector('body', 'car_type', _body, vehicleBodyTypes,
                              (v) => _body = v),
                          _field('seller_phone', 'field_phone_or_wa',
                              type: TextInputType.phone),
                          _field('description', 'field_desc',
                              type: TextInputType.multiline, lines: 3),
                        ],
                      ])),
              actions: [
                if (message != null)
                  SizedBox(
                      width: double.infinity,
                      child: Semantics(
                          liveRegion: true,
                          child: Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(message,
                                  style: TextStyle(color: scheme.error))))),
                TextButton(
                    style: TextButton.styleFrom(
                        textStyle: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontSize: 14)),
                    onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                    child: Text(t('common_cancel'))),
                FilledButton(
                    style: FilledButton.styleFrom(
                        textStyle: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontSize: 14)),
                    onPressed: _saving ? null : _submit,
                    child: _saving
                        ? SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: scheme.onPrimary))
                        : Text(t(
                            widget.delete ? 'common_delete' : 'common_save'))),
              ],
            )));
  }
}
