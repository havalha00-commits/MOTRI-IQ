/// محرّك البحث الذكي: يحوّل ما يكتبه المستخدم إلى شروط على `public.cars`.
///
/// لماذا ملف مستقل
/// ---------------
///
/// تفكيك النص إلى شروط هو الجزء الوحيد الذي يحتاج اختبارًا، وهو لا يعتمد على
/// أي Widget ولا على Supabase. فصله هنا يبقيه قابلًا للاختبار مباشرة ويمنع
/// `main.dart` من أن ينمو.
///
/// أسماء الأعمدة
/// -------------
///
/// جدول `public.cars` فيه ٢٢ عمودًا، والأسماء المطلوبة في المواصفة تختلف عن
/// المستعملة فعليًا (متحقَّق منها في `supabase/seed_30_demo_cars.sql`):
///
/// | المطلوب     | العمود الفعلي                        |
/// |-------------|--------------------------------------|
/// | `brand`     | `brand`                              |
/// | `model`     | `model`                              |
/// | `year`      | `year`                               |
/// | `price`     | `price`                              |
/// | `location`  | `city` + `province` + `governorate`  |
/// | `fuel_type` | **`fuel`**                           |
/// | `gearbox`   | **`transmission`**                   |
/// | `mileage`   | `mileage`                            |
/// | `status`    | `status`                             |
library;

/// عمود واحد يُبحث فيه.
const String kCarColBrand = 'brand';
const String kCarColModel = 'model';
const String kCarColYear = 'year';
const String kCarColPrice = 'price';
const String kCarColCity = 'city';
const String kCarColProvince = 'province';
const String kCarColGovernorate = 'governorate';
const String kCarColFuel = 'fuel';
const String kCarColTransmission = 'transmission';
const String kCarColMileage = 'mileage';
const String kCarColBodyType = 'body_type';

// PostgreSQL integer columns (including saved_searches year bounds).
const int maxSearchInteger = 2147483647;

String normalizeSearchNumber(String value) => normalizeForSearch(value)
    .replaceAll(RegExp(r'[\s,،٬]'), '')
    .replaceAll('٫', '.')
    .trim();

/// نوع الشرط المستخرَج من رمز واحد.
enum SearchFieldKind {
  brand,
  model,
  year,
  city,
  fuel,
  transmission,
  bodyType,
  free
}

/// محارف بناء جملة `or()` في PostgREST. دخولها من مربع بحث يغيّر الاستعلام بدل
/// أن يبحث فيه، فتُحذف قبل الإرسال.
const Set<String> _reservedPatternChars = <String>{
  '%',
  '_',
  '.',
  ',',
  '(',
  ')',
  r'\',
  '"',
  "'",
  ' ',
};

/// يوحّد شكل النص **للمقارنة فقط**، ولا تُستعمل نتيجته في `ilike`.
///
/// العربية تكتب «المدينة» بحاء تاء مربوطة وتطبيعها يعطي «المدينه»، وهي لا
/// تطابق القيمة المخزَّنة. لذلك التطبيع يكتشف نوع الرمز فقط، أما القيمة
/// المُرسَلة للقاعدة فتبقى من النص الأصلي أو من اسم القاموس المعياري.
String normalizeForSearch(String input) {
  final StringBuffer out = StringBuffer();
  for (final int rune in input.runes) {
    // التشكيل والعلامات الفوقية والتطويل لا تُحمل معنى في البحث.
    if ((rune >= 0x064B && rune <= 0x0652) ||
        rune == 0x0640 ||
        rune == 0x0670) {
      continue;
    }
    // الأرقام العربية-الهندية والفارسية إلى ASCII.
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + (rune - 0x0660));
      continue;
    }
    if (rune >= 0x06F0 && rune <= 0x06F9) {
      out.writeCharCode(0x30 + (rune - 0x06F0));
      continue;
    }
    final String ch = String.fromCharCode(rune).toLowerCase();
    switch (ch) {
      case 'أ':
      case 'إ':
      case 'آ':
      case 'ٱ':
        out.write('ا');
        continue;
      case 'ى':
        out.write('ي');
        continue;
      case 'ة':
        out.write('ه');
        continue;
      case 'ؤ':
        out.write('و');
        continue;
      case 'ئ':
        out.write('ي');
        continue;
    }
    out.write(ch);
  }
  return out.toString();
}

/// يزيل محارف بناء الجملة من قيمة يدخلها المستخدم.
String sanitizePattern(String value) {
  final StringBuffer out = StringBuffer();
  for (final int rune in value.runes) {
    final String ch = String.fromCharCode(rune);
    if (_reservedPatternChars.contains(ch)) continue;
    out.write(ch);
  }
  return out.toString();
}

/// قيم احتياطية لقائمة الوقود، تُضاف إن كانت القاعدة لم تعطِ شيئًا.
///
/// تُعرض مع ما وجد في القاعدة ولا تحلّ محلها: إن كانت القاعدة فيها
/// «ديزل» وحده، يظهر «ديزل» ثم الاحتياطيات.
const List<String> searchFuelFallbacks = <String>[
  'بنزين',
  'ديزل',
  'هجين',
  'كهربائية',
];

/// قيم احتياطية للقير. كل قيم القاعدة تبدأ بـ«أوتوماتيك» ثم عدد السرعات.
const List<String> searchTransmissionFallbacks = <String>[
  'أوتوماتيك',
  'أوتوماتيك 4 سرعات',
  'أوتوماتيك 6 سرعات',
  'أوتوماتيك 8 سرعات',
];

/// يدمج ما وجد في القاعدة مع الاحتياطيات بلا تكرار.
List<String> mergedOptions(List<String>? fromDatabase, List<String> fallbacks) {
  final Set<String> merged = <String>{...?fromDatabase, ...fallbacks};
  return merged.toList()..sort();
}

/// الماركات: المفتاح مطبَّع، والقيمة الاسم الذي تخزّنه القاعدة.
///
/// الماركات مخزَّنة بحروف لاتينية بحرفها الكبير، فالثيم العربي يُحوَّل إلى
/// الاسم اللاتيني قبل الإرسال — وهو ما يجعل «نيسان» تطابق `Nissan`.
const Map<String, String> _brandAliases = <String, String>{
  'nissan': 'Nissan',
  'نيسان': 'Nissan',
  'نيسن': 'Nissan',
  'نيسون': 'Nissan',
  'toyota': 'Toyota',
  'تويوتا': 'Toyota',
  'طويوتا': 'Toyota',
  'تویوتا': 'Toyota',
  'kia': 'Kia',
  'كيا': 'Kia',
  'کیا': 'Kia',
  'hyundai': 'Hyundai',
  'هيونداي': 'Hyundai',
  'هيوندا': 'Hyundai',
  'ford': 'Ford',
  'فورد': 'Ford',
  'chevrolet': 'Chevrolet',
  'شيفروليه': 'Chevrolet',
  'شفروليه': 'Chevrolet',
  'bmw': 'BMW',
  'بي ام دبليو': 'BMW',
  'audi': 'Audi',
  'اودي': 'Audi',
  'mercedes': 'Mercedes',
  'مرسيدس': 'Mercedes',
  'lexus': 'Lexus',
  'لكزس': 'Lexus',
  'mazda': 'Mazda',
  'مازدا': 'Mazda',
  'honda': 'Honda',
  'suzuki': 'Suzuki',
  'سوزوكي': 'Suzuki',
  'mitsubishi': 'Mitsubishi',
  'ميتسوبيشي': 'Mitsubishi',
  'peugeot': 'Peugeot',
  'بيجو': 'Peugeot',
  'renault': 'Renault',
  'رينو': 'Renault',
  'volkswagen': 'Volkswagen',
  'فولكس فاغن': 'Volkswagen',
  'volvo': 'Volvo',
  'فولفو': 'Volvo',
  'tesla': 'Tesla',
  'تسلا': 'Tesla',
  'haval': 'Haval',
  'هافال': 'Haval',
  'chery': 'Chery',
  'شيري': 'Chery',
  'jetour': 'Jetour',
  'جيتور': 'Jetour',
  'byd': 'BYD',
  'بي واي دي': 'BYD',
  'mg': 'MG',
  'ام جي': 'MG',
  'geely': 'Geely',
  'جيلي': 'Geely',
  'gac': 'GAC',
  'جاك': 'GAC',
};

/// الموديلات، بالسبب نفسه.
const Map<String, String> _modelAliases = <String, String>{
  'camry': 'Camry',
  'كامري': 'Camry',
  'corolla': 'Corolla',
  'كورولا': 'Corolla',
  'patrol': 'Patrol',
  'باترول': 'Patrol',
  'sunny': 'Sunny',
  'صني': 'Sunny',
  'سوني': 'Sunny',
  'civic': 'Civic',
  'سيفك': 'Civic',
  'accord': 'Accord',
  'اكورد': 'Accord',
  'mustang': 'Mustang',
  'ماستنغ': 'Mustang',
  'hilux': 'Hilux',
  'هايلكس': 'Hilux',
  'landcruiser': 'Land Cruiser',
  'لاند كروزر': 'Land Cruiser',
  'tahoe': 'Tahoe',
  'تاهو': 'Tahoe',
  'suburban': 'Suburban',
  'سوبربن': 'Suburban',
  'yaris': 'Yaris',
  'يارس': 'Yaris',
  'prius': 'Prius',
  'بريوس': 'Prius',
  'sportage': 'Sportage',
  'سبورتاج': 'Sportage',
  'tucson': 'Tucson',
  'توكسون': 'Tucson',
  'ranger': 'Ranger',
  'رينجر': 'Ranger',
  'fortuner': 'Fortuner',
  'فورتنر': 'Fortuner',
  'prado': 'Prado',
  'برادو': 'Prado',
  'crv': 'CR-V',
  'landrover': 'Land Rover',
  'لاند روفر': 'Land Rover',
};

/// أنواع الوقود — القيم هي ما تخزّنه القاعدة نصًّا عربيًّا.
const Map<String, String> _fuelAliases = <String, String>{
  'بنزين': 'بنزين',
  'petrol': 'بنزين',
  'gasoline': 'بنزين',
  'benzin': 'بنزين',
  'ديزل': 'ديزل',
  'diesel': 'ديزل',
  'هجين': 'هجين',
  'hybrid': 'هجين',
  'كهربائيه': 'كهربائية',
  'كهربائية': 'كهربائية',
  'electric': 'كهربائية',
  'ev': 'كهربائية',
};

/// ناقل الحركة. يُطابَق على بادئة الكلمة لا على القيمة كاملة: كل القيم
/// المخزَّنة تبدأ بـ«أوتوماتيك» متبوعةً بعدد السرعات («أوتوماتيك 8 سرعات»)،
/// فـ`eq('أوتوماتيك')` وحده يفوّت أغلب السيارات.
const Map<String, String> _transmissionAliases = <String, String>{
  'اوتوماتيك': 'أوتوماتيك',
  'automatic': 'أوتوماتيك',
  'auto': 'أوتوماتيك',
};

/// أنواع الهيكل — نفس قيم `vehicleBodyTypes` في `main.dart`، مكرَّرة هنا عمدًا
/// حتى لا يعتمد هذا الملف على `main.dart`.
const List<String> searchBodyTypes = <String>[
  'سيدان',
  'SUV',
  'هاتشباك',
  'بيك أب',
  'فان',
  'كوبيه',
  'أخرى',
];

/// القيم المعيارية التي يبدأ أيٌّ من أسمائها المستعار بـ[bounded].
///
/// هذه هي الجسر بين العربية واللاتينية: التطبيع وحده لا يحوّل «نيس» إلى
/// `Nissan` لأن الحرفين من نظامين مختلفين، بينما القاموس يربط بينهما.
List<String> canonicalValuesStartingWith(String bounded) {
  final String needle = normalizeForSearch(bounded.trim());
  if (needle.isEmpty) return const <String>[];
  final List<String> out = <String>[];
  for (final Map<String, String> table in <Map<String, String>>[
    _brandAliases,
    _modelAliases,
  ]) {
    for (final MapEntry<String, String> entry in table.entries) {
      final String aliasKey = normalizeForSearch(entry.key);
      if (!aliasKey.startsWith(needle) && !aliasKey.contains(needle)) continue;
      if (!out.contains(entry.value)) out.add(entry.value);
    }
  }
  return out;
}

/// هل [value] اسم ماركة معروف في القاموس؟
bool isKnownBrand(String value) => _brandAliases.values.contains(value);

/// هل [value] اسم موديل معروف في القاموس؟
bool isKnownModel(String value) => _modelAliases.values.contains(value);

Map<String, String> _bodyTypeAliases() {
  final Map<String, String> map = <String, String>{};
  for (final String type in searchBodyTypes) {
    map[normalizeForSearch(type)] = type;
  }
  return map;
}

/// شرط واحد مستخرَج من نص البحث.
class SearchCondition {
  const SearchCondition(this.kind, this.value, this.display);

  final SearchFieldKind kind;

  /// القيمة التي تُرسل إلى القاعدة.
  final String value;

  /// النص كما كتبه المستخدم.
  final String display;

  @override
  String toString() => 'SearchCondition(${kind.name}, $value)';
}

/// خطوة استعلام واحدة.
///
/// بارامترات الفلترة المختلفة في PostgREST تُدمج بـ**AND**، وبهذا يُبنى كل
/// شرط من البحث الذكي كبارامتر مستقل. أما البدائل التي تخصّ **عمودًا واحدًا**
/// (المدينة أو المحافظة، أو علامتان للماركة نفسها) فتُجمَع في `or` واحد، لأن
/// `or` بين قوسين هو **OR** — وهو المطلوب داخل الحقل الواحد فقط.
///
/// الخطأ الذي يمنع هذا البناء: وضع كل الشروط في `or` واحد. عندها يصبح
/// «نيسان 2022» يعني «نيسان **أو** 2022»، فيظهر كل نيسان مهما كانت سنته.
class QueryStep {
  const QueryStep.direct(this.column, this.operator, this.value)
      : clauses = null;

  const QueryStep.group(List<String> this.clauses)
      : column = '',
        operator = '',
        value = '';

  /// مرشّح مباشر: `عمود.مشغّل.قيمة`
  final String column;
  final String operator;
  final String value;

  /// مجموعة بدائل تُدمج بـOR على عمود واحد.
  final List<String>? clauses;

  bool get isGroup => clauses != null;

  @override
  String toString() => isGroup
      ? 'QueryStep.group($clauses)'
      : 'QueryStep.$column.$operator.$value';
}

List<String>? _clean(List<String> values) {
  final List<String> out = <String>[
    for (final String value in values)
      if (sanitizePattern(value).isNotEmpty) value,
  ];
  return out.isEmpty ? null : out;
}

/// نتيجة تفكيك مربع البحث إلى شروط.
class SmartQuery {
  SmartQuery._(this.raw, this.conditions, this.freeTokens);

  final String raw;
  final List<SearchCondition> conditions;

  /// رموز لم يُعرف نوعها، تُطابَق على الموقع ثم على العنوان.
  final List<String> freeTokens;

  bool get isEmpty => conditions.isEmpty && freeTokens.isEmpty;

  List<String> valuesOf(SearchFieldKind kind) => <String>[
        for (final SearchCondition c in conditions)
          if (c.kind == kind) c.value,
      ];

  bool get hasBrand => valuesOf(SearchFieldKind.brand).isNotEmpty;
  bool get hasModel => valuesOf(SearchFieldKind.model).isNotEmpty;

  /// يفكّك `raw` إلى شروط.
  ///
  /// «تويوتا كامري بغداد 2022» ينتج أربع شروط — ماركة وموديل وموقع وسنة —
  /// فتُدمج كلها في استعلام واحد بدل أربعة استعلامات.
  static SmartQuery parse(String raw) {
    final List<SearchCondition> conditions = <SearchCondition>[];
    final List<String> free = <String>[];
    final Map<String, String> bodyAliases = _bodyTypeAliases();

    for (final String token in raw.split(RegExp(r'\s+'))) {
      // محارف بناء الجملة تُحذف قبل التعرّف على نوع الرمز: فاصلة زائدة من
      // المستخدم يجب ألّا تحوّل «نيسان» من ماركة إلى رمز مجهول.
      final String clean = sanitizePattern(token);
      if (clean.isEmpty) continue;
      final String norm = normalizeForSearch(clean);
      if (norm.isEmpty) continue;

      // السنة: أربعة أرقام داخل نطاق معقول.
      final int? year = int.tryParse(norm);
      if (year != null && year >= 1950 && year <= 2100) {
        conditions.add(SearchCondition(SearchFieldKind.year, '$year', clean));
        continue;
      }

      final String? brand = _brandAliases[norm];
      if (brand != null) {
        conditions.add(SearchCondition(SearchFieldKind.brand, brand, clean));
        continue;
      }

      final String? model = _modelAliases[norm];
      if (model != null) {
        conditions.add(SearchCondition(SearchFieldKind.model, model, clean));
        continue;
      }

      final String? fuel = _fuelAliases[norm];
      if (fuel != null) {
        conditions.add(SearchCondition(SearchFieldKind.fuel, fuel, clean));
        continue;
      }

      final String? transmission = _transmissionAliases[norm];
      if (transmission != null) {
        conditions.add(
            SearchCondition(SearchFieldKind.transmission, transmission, clean));
        continue;
      }

      final String? bodyType = bodyAliases[norm];
      if (bodyType != null) {
        conditions
            .add(SearchCondition(SearchFieldKind.bodyType, bodyType, clean));
        continue;
      }

      free.add(clean);
    }

    return SmartQuery._(raw, conditions, free);
  }

  /// خطوات الاستعلام — كل شرط في بارامتر مستقل حتى يُدمج بـAND.
  List<QueryStep> get steps {
    final List<QueryStep> out = <QueryStep>[];

    void add(String column, String operator, List<String> values) {
      final List<String>? cleaned = _clean(values);
      if (cleaned == null) return;
      if (cleaned.length == 1) {
        out.add(QueryStep.direct(
            column, operator, '%${sanitizePattern(cleaned.first)}%'));
        return;
      }
      out.add(QueryStep.group(<String>[
        for (final String value in cleaned)
          '$column.$operator.%${sanitizePattern(value)}%',
      ]));
    }

    void addExact(String column, List<String> values) {
      final List<String>? cleaned = _clean(values);
      if (cleaned == null) return;
      if (cleaned.length == 1) {
        out.add(QueryStep.direct(column, 'eq', cleaned.first));
        return;
      }
      out.add(QueryStep.group(<String>[
        for (final String value in cleaned) '$column.eq.$value',
      ]));
    }

    add(kCarColBrand, 'ilike', valuesOf(SearchFieldKind.brand));
    add(kCarColModel, 'ilike', valuesOf(SearchFieldKind.model));
    addExact(kCarColYear, valuesOf(SearchFieldKind.year));
    add(kCarColFuel, 'ilike', valuesOf(SearchFieldKind.fuel));
    add(kCarColTransmission, 'ilike', valuesOf(SearchFieldKind.transmission));
    add(kCarColBodyType, 'ilike', valuesOf(SearchFieldKind.bodyType));

    // الرمز المجهول يُطابَق على الموقع أولًا («بغداد») ثم على العنوان. هذه
    // بدائل لعمود واحد، فتكفي مجموعة OR واحدة لكل رمز.
    for (final String token in freeTokens) {
      final String pattern = sanitizePattern(token);
      if (pattern.isEmpty) continue;
      out.add(QueryStep.group(<String>[
        '$kCarColCity.ilike.%$pattern%',
        '$kCarColProvince.ilike.%$pattern%',
        '$kCarColGovernorate.ilike.%$pattern%',
        'title.ilike.%$pattern%',
      ]));
    }

    return out;
  }

  /// خطوة `or` واحدة مدمجة، للاستخدام خارج المتغيّرات (الاختبار والتشخيص).
  ///
  /// تحذير: هذه **OR** بين كل الشروط، فلا تُستخدم لبناء استعلام فعلي متعدد
  /// الشروط — استعمل [steps].
  String? get orClause {
    final List<String> all = <String>[
      for (final QueryStep step in steps)
        if (step.isGroup)
          ...step.clauses!
        else
          '${step.column}.${step.operator}.${step.value}',
    ];
    return all.isEmpty ? null : all.join(',');
  }

  /// وصف الشروط للاختبار والتشخيص.
  String get describe => conditions.isEmpty && freeTokens.isEmpty
      ? '(empty)'
      : <String>[
          ...conditions.map((SearchCondition c) => '${c.kind.name}=${c.value}'),
          ...freeTokens.map((String token) => 'location=$token'),
        ].join(' + ');
}

/// خطة استعلام جاهزة للتطبيق: شروط نصّية ونطاقات رقمية.
///
/// هنا فقط تُحوَّل النصوص إلى أرقام، و`null` يعني «بلا قيد» فلا يُرسل شيء.
class FilterPlan {
  const FilterPlan({
    required this.steps,
    this.lowYear,
    this.highYear,
    this.lowPrice,
    this.highPrice,
    this.maxMileage,
  });

  final List<QueryStep> steps;
  final int? lowYear;
  final int? highYear;
  final num? lowPrice;
  final num? highPrice;
  final num? maxMileage;

  bool get isEmpty =>
      steps.isEmpty &&
      lowYear == null &&
      highYear == null &&
      lowPrice == null &&
      highPrice == null &&
      maxMileage == null;
}

/// فلاتر متقدمة تُختار من ورقة منبثقة، لا من نص البحث.
class CarSearchFilters {
  String brand = '';
  String model = '';
  String city = '';
  String bodyType = '';
  String fromYear = '';
  String toYear = '';
  String minPrice = '';
  String maxPrice = '';
  String province = '';
  String fuel = '';
  String transmission = '';
  String maxMileage = '';

  bool get isEmpty =>
      brand.trim().isEmpty &&
      model.trim().isEmpty &&
      city.trim().isEmpty &&
      bodyType.trim().isEmpty &&
      fromYear.trim().isEmpty &&
      toYear.trim().isEmpty &&
      minPrice.trim().isEmpty &&
      maxPrice.trim().isEmpty &&
      province.trim().isEmpty &&
      fuel.trim().isEmpty &&
      transmission.trim().isEmpty &&
      maxMileage.trim().isEmpty;

  bool get isNotEmpty => !isEmpty;

  void clear() {
    brand = '';
    model = '';
    city = '';
    bodyType = '';
    fromYear = '';
    toYear = '';
    minPrice = '';
    maxPrice = '';
    province = '';
    fuel = '';
    transmission = '';
    maxMileage = '';
  }

  CarSearchFilters copy() => CarSearchFilters()
    ..brand = brand
    ..model = model
    ..city = city
    ..bodyType = bodyType
    ..fromYear = fromYear
    ..toYear = toYear
    ..minPrice = minPrice
    ..maxPrice = maxPrice
    ..province = province
    ..fuel = fuel
    ..transmission = transmission
    ..maxMileage = maxMileage;

  /// وصف مختصر للفلاتر النشطة، لعرضها كرقائق تحت مربع البحث.
  List<String> get activeLabels => <String>[
        if (brand.trim().isNotEmpty) brand.trim(),
        if (model.trim().isNotEmpty) model.trim(),
        if (city.trim().isNotEmpty) city.trim(),
        if (bodyType.trim().isNotEmpty) bodyType.trim(),
        if (fromYear.trim().isNotEmpty || toYear.trim().isNotEmpty)
          '${fromYear.trim()}-${toYear.trim()}',
        if (minPrice.trim().isNotEmpty || maxPrice.trim().isNotEmpty)
          '${minPrice.trim()}-${maxPrice.trim()}',
        if (province.trim().isNotEmpty) province.trim(),
        if (fuel.trim().isNotEmpty) fuel.trim(),
        if (transmission.trim().isNotEmpty) transmission.trim(),
        if (maxMileage.trim().isNotEmpty) maxMileage.trim(),
      ];

  String? get numericError {
    final integers =
        [fromYear, toYear, maxMileage].map(normalizeSearchNumber).toList();
    final prices = [minPrice, maxPrice].map(normalizeSearchNumber).toList();
    for (final value in integers.where((value) => value.isNotEmpty)) {
      final parsed = int.tryParse(value);
      if (!RegExp(r'^\d+$').hasMatch(value) ||
          parsed == null ||
          parsed > maxSearchInteger) {
        return 'search_invalid_number';
      }
    }
    for (final value in prices.where((value) => value.isNotEmpty)) {
      final parsed = double.tryParse(value);
      if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value) ||
          parsed == null ||
          !parsed.isFinite) {
        return 'search_invalid_number';
      }
    }
    if (integers[0].isNotEmpty &&
        integers[1].isNotEmpty &&
        int.parse(integers[0]) > int.parse(integers[1])) {
      return 'search_invalid_year_range';
    }
    if (prices[0].isNotEmpty &&
        prices[1].isNotEmpty &&
        double.parse(prices[0]) > double.parse(prices[1])) {
      return 'search_invalid_price_range';
    }
    return null;
  }

  FilterPlan get plan {
    final List<QueryStep> steps = <QueryStep>[];

    void add(String column, List<String> values) {
      final List<String> cleaned = <String>[
        for (final String value in values)
          if (sanitizePattern(value.trim()).isNotEmpty) value.trim(),
      ];
      if (cleaned.isEmpty) return;
      if (cleaned.length == 1) {
        steps.add(QueryStep.direct(
            column, 'ilike', '%${sanitizePattern(cleaned.first)}%'));
        return;
      }
      steps.add(QueryStep.group(<String>[
        for (final String value in cleaned)
          '$column.ilike.%${sanitizePattern(value)}%',
      ]));
    }

    add(kCarColBrand, <String>[brand]);
    add(kCarColModel, <String>[model]);
    add('city', <String>[city]);
    if (bodyType.trim().isNotEmpty) {
      steps.add(QueryStep.direct('body_type', 'eq', bodyType.trim()));
    }
    add(kCarColFuel, <String>[fuel]);
    add(kCarColTransmission, <String>[transmission]);
    // المحافظة خطآن في الجدول، فيُطابَق على العمودين معًا.
    final String provinceCleaned = sanitizePattern(province.trim());
    if (provinceCleaned.isNotEmpty) {
      steps.add(QueryStep.group(<String>[
        '$kCarColProvince.ilike.%$provinceCleaned%',
        '$kCarColGovernorate.ilike.%$provinceCleaned%',
      ]));
    }

    return FilterPlan(
      steps: steps,
      lowYear: int.tryParse(normalizeSearchNumber(fromYear)),
      highYear: int.tryParse(normalizeSearchNumber(toYear)),
      lowPrice: num.tryParse(normalizeSearchNumber(minPrice)),
      highPrice: num.tryParse(normalizeSearchNumber(maxPrice)),
      maxMileage: num.tryParse(normalizeSearchNumber(maxMileage)),
    );
  }
}
