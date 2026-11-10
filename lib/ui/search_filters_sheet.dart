import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../search/smart_query.dart';
import 'content_direction.dart';

/// Owns its controllers until the closing route animation has finished.
class SearchFiltersSheet extends StatefulWidget {
  const SearchFiltersSheet(
      {super.key,
      required this.initial,
      required this.provinces,
      required this.fuels,
      required this.transmissions,
      this.bodyTypes = const []});
  final CarSearchFilters initial;
  final List<String> provinces;
  final List<String> fuels;
  final List<String> transmissions;
  final List<String> bodyTypes;

  @override
  State<SearchFiltersSheet> createState() => _SearchFiltersSheetState();
}

class _SearchFiltersSheetState extends State<SearchFiltersSheet> {
  late final CarSearchFilters draft = widget.initial.copy();
  late final fields = <String, TextEditingController>{
    'brand': TextEditingController(text: draft.brand),
    'model': TextEditingController(text: draft.model),
    'city': TextEditingController(text: draft.city),
    'fromYear': TextEditingController(text: draft.fromYear),
    'toYear': TextEditingController(text: draft.toYear),
    'minPrice': TextEditingController(text: draft.minPrice),
    'maxPrice': TextEditingController(text: draft.maxPrice),
    'maxMileage': TextEditingController(text: draft.maxMileage),
  };
  String? errorKey;

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String numeric(String field) => normalizeForSearch(fields[field]!.text)
      .replaceAll(RegExp(r'[\s,،٬]'), '')
      .replaceAll('٫', '.')
      .trim();

  void apply() {
    final values = {
      for (final key in [
        'fromYear',
        'toYear',
        'minPrice',
        'maxPrice',
        'maxMileage'
      ])
        key: numeric(key)
    };
    final numericDraft = CarSearchFilters()
      ..fromYear = values['fromYear']!
      ..toYear = values['toYear']!
      ..minPrice = values['minPrice']!
      ..maxPrice = values['maxPrice']!
      ..maxMileage = values['maxMileage']!;
    final error = numericDraft.numericError;
    if (error != null) {
      setState(() => errorKey = error);
      return;
    }
    draft
      ..brand = fields['brand']!.text.trim()
      ..model = fields['model']!.text.trim()
      ..city = fields['city']!.text.trim()
      ..fromYear = values['fromYear']!
      ..toYear = values['toYear']!
      ..minPrice = values['minPrice']!
      ..maxPrice = values['maxPrice']!
      ..maxMileage = values['maxMileage']!;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(draft);
  }

  Widget field(String key, String label, IconData icon, {bool number = false}) {
    Widget input(TextDirection direction) => TextField(
          key: ValueKey('filter_$key'),
          controller: fields[key],
          textDirection: direction,
          textInputAction: TextInputAction.next,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          onChanged: (_) {
            if (errorKey != null) setState(() => errorKey = null);
          },
          decoration: InputDecoration(
              labelText: t(label), prefixIcon: Icon(icon, size: 20)),
        );
    if (number) return input(TextDirection.ltr);
    return ContentDirectionBuilder(
      controller: fields[key]!,
      builder: (context, direction) => input(direction),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height =
        (media.size.height - media.viewInsets.bottom - media.padding.top) * 0.9;
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
          top: false,
          child: SizedBox(
              height: height,
              child: Column(children: [
                Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 8),
                    child: Row(children: [
                      Expanded(
                          child: Text(t('search_filters_title'),
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded)),
                    ])),
                const Divider(height: 1),
                Expanded(
                    child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          field('brand', 'field_brand',
                              Icons.directions_car_outlined),
                          const SizedBox(height: 12),
                          field('model', 'field_model',
                              Icons.car_rental_outlined),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: field('fromYear', 'req_from_year',
                                    Icons.calendar_month_outlined,
                                    number: true)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: field('toYear', 'req_to_year',
                                    Icons.calendar_month_outlined,
                                    number: true)),
                          ]),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                                child: field('minPrice', 'search_price_low',
                                    Icons.attach_money,
                                    number: true)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: field('maxPrice', 'search_price_high',
                                    Icons.attach_money,
                                    number: true)),
                          ]),
                          const SizedBox(height: 12),
                          field(
                              'city', 'field_city', Icons.location_on_outlined),
                          const SizedBox(height: 12),
                          if (widget.bodyTypes.isNotEmpty) ...[
                            StableFilterDropdown(
                                label: t('car_type'),
                                value: draft.bodyType,
                                options: widget.bodyTypes,
                                onChanged: (v) =>
                                    setState(() => draft.bodyType = v)),
                            const SizedBox(height: 12),
                          ],
                          StableFilterDropdown(
                              label: t('field_province'),
                              value: draft.province,
                              options: widget.provinces,
                              onChanged: (v) =>
                                  setState(() => draft.province = v)),
                          const SizedBox(height: 12),
                          StableFilterDropdown(
                              label: t('field_fuel'),
                              value: draft.fuel,
                              options: widget.fuels,
                              onChanged: (v) => setState(() => draft.fuel = v)),
                          const SizedBox(height: 12),
                          StableFilterDropdown(
                              label: t('field_transmission'),
                              value: draft.transmission,
                              options: widget.transmissions,
                              onChanged: (v) =>
                                  setState(() => draft.transmission = v)),
                          const SizedBox(height: 12),
                          field('maxMileage', 'field_mileage_max',
                              Icons.speed_outlined,
                              number: true),
                        ]))),
                if (errorKey != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Semantics(
                          liveRegion: true,
                          child: Text(t(errorKey!),
                              style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.error)))),
                const Divider(height: 1),
                Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                              onPressed: apply,
                              icon: const Icon(Icons.check_rounded),
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(48)),
                              label: Text(t('search_apply'),
                                  textAlign: TextAlign.center)),
                          TextButton.icon(
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                Navigator.pop(context, CarSearchFilters());
                              },
                              icon: const Icon(Icons.restart_alt_rounded),
                              label: Text(t('search_reset'))),
                        ])),
              ]))),
    );
  }
}

/// Keep actual database values stable while labels and form state can rebuild.
class StableFilterDropdown extends StatelessWidget {
  const StableFilterDropdown(
      {super.key,
      required this.label,
      required this.value,
      required this.options,
      required this.onChanged});
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final choices = <String>{
      ...options.map((e) => e.trim()).where((e) => e.isNotEmpty),
      if (value.isNotEmpty) value
    };
    return DropdownButtonFormField<String>(
      key: ValueKey('$label:$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        DropdownMenuItem(value: '', child: Text(t('common_all'))),
        for (final choice in choices)
          DropdownMenuItem(
              value: choice,
              child: Text(choice, maxLines: 1, overflow: TextOverflow.ellipsis))
      ],
      onChanged: (v) => onChanged(v ?? ''),
    );
  }
}
