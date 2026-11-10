/// مفردات البحث: القيم الفعلية الموجودة في جدول السيارات.
///
/// لماذا من القاعدة وليست قوائم ثابتة
/// ---------------------------------
///
/// قوائم الماركات والموديلات والمدن لا يمكن كتابتها في الشيفرة: أي سيارة يضيفها
/// بائع تستحق أن تُقترح. لذلك تُقرأ القيم المميزة بعمود واحد خفيف عند أول
/// استخدام، ثم تُحفظ في الذاكرة.
library;

import '../backend_api.dart';

import 'smart_query.dart';

/// اقتراح واحد يظهر تحت مربع البحث.
class SearchSuggestion {
  const SearchSuggestion({
    required this.display,
    required this.replacement,
    required this.kind,
  });

  /// النص المعروض في قائمة الاقتراحات.
  final String display;

  /// النص الذي يُكتب في مربع البحث عند الاختيار.
  final String replacement;

  final SearchFieldKind kind;
}

/// القيم المميزة الموجودة فعلًا في `cars`.
class SearchVocabulary {
  SearchVocabulary({
    required this.brands,
    required this.models,
    required this.composites,
    required this.cities,
    required this.provinces,
    required this.fuels,
    required this.transmissions,
    required this.bodyTypes,
  });

  final List<String> brands;
  final List<String> models;

  /// تركيبات «ماركة موديل» الموجودة فعلًا، مثل «نيسان باترول».
  final List<String> composites;

  final List<String> cities;
  final List<String> provinces;
  final List<String> fuels;
  final List<String> transmissions;
  final List<String> bodyTypes;

  bool get isEmpty => brands.isEmpty && models.isEmpty;

  /// أقصى عدد اقتراحات معروضة، حتى لا تطول القائمة بلا فائدة.
  static const int _maxSuggestions = 8;

  /// يقترح ما يطابق ما يكتبه المستخدم.
  ///
  /// المطابقة تمرّ بمصدرين:
  ///
  ///  1. القاموس — «نيس» تصل إلى `Nissan` لأن الاسم المستعار «نيسان» يبدأ
  ///     بها. التطبيع وحده لا يفعل ذلك، فالحرفان من نظامين مختلفين.
  ///  2. القيم الحقيقية في القاعدة — وهي التي تجعل «نيسان باترول» تظهر، لأنها
  ///     تركيبة موجودة فعلًا لا تخيّلًا.
  ///
  /// الترتيب: الماركة أولًا، ثم ما يرتبط بها من تركيبات، ثم الموديلات،
  /// ثم الموقع والوقود — لأن «نيسان» أخص من «نيسان باترول».
  List<SearchSuggestion> suggest(String text, {int limit = _maxSuggestions}) {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return const <SearchSuggestion>[];

    // نص متعدد الكلمات يُقترح على آخر رمز مكتوب: بعد كتابة «تويوتا كامري»
    // المقصود إكمال الموديل لا إعادة اقتراح الماركة.
    final String needle = trimmed.contains(' ')
        ? trimmed.split(RegExp(r'\s+')).last
        : trimmed;
    final String norm = normalizeForSearch(needle);
    if (norm.isEmpty) return const <SearchSuggestion>[];

    final List<SearchSuggestion> out = <SearchSuggestion>[];

    void offer(String value, SearchFieldKind kind) {
      if (out.length >= limit) return;
      if (value.trim().isEmpty) return;
      if (out.any((SearchSuggestion s) => s.display == value)) return;
      out.add(
          SearchSuggestion(display: value, replacement: value, kind: kind));
    }

    bool matches(String value) {
      final String candidate = normalizeForSearch(value);
      return candidate.startsWith(norm) || candidate.contains(norm);
    }

    // 1) الماركات والموديلات عبر القاموس، ثم ما ينتمي إلى كل ماركة.
    final List<String> canonical = canonicalValuesStartingWith(needle);
    for (final String value in canonical) {
      offer(
        value,
        isKnownBrand(value) ? SearchFieldKind.brand : SearchFieldKind.model,
      );
      if (!isKnownBrand(value)) continue;
      final String brandNorm = normalizeForSearch(value);
      for (final String composite in composites) {
        if (normalizeForSearch(composite).startsWith('$brandNorm ')) {
          offer(composite, SearchFieldKind.brand);
        }
      }
      for (final String model in models) {
        if (normalizeForSearch(model).startsWith(brandNorm)) {
          offer(model, SearchFieldKind.model);
        }
      }
    }

    // 2) القيم الحقيقية، مطابقةً على البادئة أولًا ثم على أي موضع.
    for (final String value in brands.where(matches)) {
      offer(value, SearchFieldKind.brand);
    }
    for (final String value in composites.where(matches)) {
      offer(value, SearchFieldKind.brand);
    }
    for (final String value in models.where(matches)) {
      offer(value, SearchFieldKind.model);
    }
    for (final String city in cities.where(matches)) {
      offer(city, SearchFieldKind.city);
    }
    for (final String value in provinces.where(matches)) {
      offer(value, SearchFieldKind.city);
    }
    for (final String value in fuels.where(matches)) {
      offer(value, SearchFieldKind.fuel);
    }
    for (final String value in transmissions.where(matches)) {
      offer(value, SearchFieldKind.transmission);
    }
    for (final String value in bodyTypes.where(matches)) {
      offer(value, SearchFieldKind.bodyType);
    }

    return out.take(limit).toList();
  }
}

/// ذاكرة مؤقتة واحدة: القراءة进行一次 فقط لكل تشغيل.
SearchVocabulary? _cache;

/// يبني المفردات من الصفوف المجلوبة.
SearchVocabulary vocabularyFromRows(List<Map<String, dynamic>> rows) {
  final Set<String> brands = <String>{};
  final Set<String> models = <String>{};
  final Set<String> composites = <String>{};
  final Set<String> cities = <String>{};
  final Set<String> provinces = <String>{};
  final Set<String> fuels = <String>{};
  final Set<String> transmissions = <String>{};
  final Set<String> bodyTypes = <String>{};

  void put(Set<String> into, Object? raw) {
    final String value = raw?.toString().trim() ?? '';
    if (value.isEmpty) return;
    into.add(value);
  }

  for (final Map<String, dynamic> row in rows) {
    put(brands, row[kCarColBrand]);
    put(models, row[kCarColModel]);
    put(cities, row[kCarColCity]);
    put(provinces, row[kCarColProvince]);
    put(fuels, row[kCarColFuel]);
    put(transmissions, row[kCarColTransmission]);
    put(bodyTypes, row[kCarColBodyType]);

    final String brand = row[kCarColBrand]?.toString().trim() ?? '';
    final String model = row[kCarColModel]?.toString().trim() ?? '';
    if (brand.isNotEmpty && model.isNotEmpty) {
      composites.add('$brand $model');
    }
  }

  List<String> sorted(Set<String> into) {
    final List<String> list = into.toList()..sort();
    return list;
  }

  return SearchVocabulary(
    brands: sorted(brands),
    models: sorted(models),
    composites: sorted(composites),
    cities: sorted(cities),
    provinces: sorted(provinces),
    fuels: sorted(fuels),
    transmissions: sorted(transmissions),
    bodyTypes: sorted(bodyTypes),
  );
}

/// يقرأ القيم المميزة إن لم تكن محفوظة، ويعيدها.
///
/// النداء الأول ينتظر الشبكة؛ النداء التالي يعيد فورًا. الفشل يعيد مفردات
/// فارغة بدل رمي استثناء، لأن الاقتراحات تحسين اختياري يجب ألا يعطّل البحث.
Future<SearchVocabulary> loadVocabulary(
  BackendApi api, {
  bool refresh = false,
}) async {
  if (!refresh && _cache != null) return _cache!;
  try {
    final response = await api.get('cars/vocabulary');
    if (response is! Map || response['data'] is! List) {
      throw StateError('Car vocabulary response is invalid');
    }
    _cache = vocabularyFromRows(
      List<Map<String, dynamic>>.from(response['data'] as List),
    );
  } catch (_) {
    _cache = vocabularyFromRows(const <Map<String, dynamic>>[]);
  }
  return _cache!;
}

/// يمسح الذاكرة المؤقتة — للاختبارات.
void clearVocabularyCache() => _cache = null;