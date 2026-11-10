import 'smart_query.dart';

/// Matches the supported predicates in create_saved_search_alerts. Never store
/// SmartQuery text as query_text: the trigger treats that text as one literal.
({Map<String, dynamic>? payload, String? error}) savedSearchCriteria({
  required String query,
  required CarSearchFilters quick,
  required CarSearchFilters advanced,
}) {
  for (final filters in [quick, advanced]) {
    final error = filters.numericError;
    if (error != null) return (payload: null, error: error);
  }
  final payload = <String, dynamic>{
    'query_text': null,
    'brand': null,
    'city': null,
    'province': null,
    'body_type': null,
    'min_year': null,
    'max_year': null,
    'min_price': null,
    'max_price': null,
  };
  bool unsupported = false;
  void mergeText(String key, String value) {
    if (payload[key] != null &&
        payload[key].toString().toLowerCase() != value.toLowerCase()) {
      unsupported = true;
    } else {
      payload[key] = value;
    }
  }

  void bound(String key, num? value, {required bool lower}) {
    if (value == null) return;
    final current = payload[key] as num?;
    if (current == null || (lower ? value > current : value < current)) {
      payload[key] = value;
    }
  }

  final steps = <QueryStep>[
    if (quick.brand.trim().isNotEmpty)
      QueryStep.direct('brand', 'ilike', '%${quick.brand.trim()}%'),
    if (quick.city.trim().isNotEmpty)
      QueryStep.direct('city', 'ilike', '%${quick.city.trim()}%'),
    if (quick.province.isNotEmpty)
      QueryStep.direct('province', 'eq', quick.province),
    if (quick.bodyType.isNotEmpty)
      QueryStep.direct('body_type', 'eq', quick.bodyType),
    ...SmartQuery.parse(query).steps,
    ...advanced.plan.steps,
  ];
  for (final step in steps) {
    if (step.isGroup) {
      unsupported = true;
      continue;
    }
    if (['brand', 'city'].contains(step.column) &&
        step.operator == 'ilike' &&
        step.value.startsWith('%') &&
        step.value.endsWith('%')) {
      mergeText(step.column, step.value.substring(1, step.value.length - 1));
    } else if (['province', 'body_type'].contains(step.column) &&
        step.operator == 'eq') {
      mergeText(step.column, step.value);
    } else if (step.column == 'year' && step.operator == 'eq') {
      final year = int.tryParse(step.value);
      if (year == null || year < 0 || year > maxSearchInteger) {
        return (payload: null, error: 'search_invalid_number');
      }
      bound('min_year', year, lower: true);
      bound('max_year', year, lower: false);
    } else {
      unsupported = true;
    }
  }
  if (advanced.maxMileage.trim().isNotEmpty) unsupported = true;
  if (unsupported) return (payload: null, error: 'ui_alert_criteria_limit');
  for (final filters in [quick, advanced]) {
    final plan = filters.plan;
    bound('min_year', plan.lowYear, lower: true);
    bound('max_year', plan.highYear, lower: false);
    bound('min_price', plan.lowPrice, lower: true);
    bound('max_price', plan.highPrice, lower: false);
  }
  for (final pair in [('min_year', 'max_year'), ('min_price', 'max_price')]) {
    final low = payload[pair.$1] as num?, high = payload[pair.$2] as num?;
    if (low != null && high != null && low > high) {
      return (
        payload: null,
        error: pair.$1 == 'min_year'
            ? 'search_invalid_year_range'
            : 'search_invalid_price_range'
      );
    }
  }
  if (payload.values.every((value) => value == null)) {
    return (payload: null, error: 'alerts_need_filter');
  }
  return (payload: payload, error: null);
}
