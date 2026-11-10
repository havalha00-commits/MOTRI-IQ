// اختبار تفكيك نص البحث إلى شروط على جدول cars.
//
// كل حالة هنا من متطلبات المواصفة حرفيًا: «نيسان» يجب أن يعيد Nissan وحدها،
// و«نيسان 2022» يجب أن يدمج شرطين في استعلام واحد.

import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/search/search_vocabulary.dart';
import 'package:motri_iq/search/smart_query.dart';

/// الخطوات بصيغة `عمود.مشغّل.قيمة` كما ستُرسَل إلى PostgREST.
String describeSteps(SmartQuery query) => query.steps
    .map((QueryStep step) => step.isGroup
        ? 'or(${step.clauses!.join('|')})'
        : '${step.column}.${step.operator}.${step.value}')
    .join(' AND ');

/// يتحقق أن الشروط المتعددة في بارامترات منفصلة. دمجها في `or` واحد يجعل
/// «نيسان 2022» يعني «نيسان **أو** 2022».
int conditionCount(SmartQuery query) => query.steps.length;

void main() {
  group('تفكيك نص البحث', () {
    test('«نيسان» becomes brand = Nissan', () {
      final SmartQuery query = SmartQuery.parse('نيسان');
      expect(query.valuesOf(SearchFieldKind.brand), <String>['Nissan']);
      expect(query.hasModel, isFalse);
      expect(query.freeTokens, isEmpty);
      expect(describeSteps(query), 'brand.ilike.%Nissan%');
    });

    test('«تويوتا» becomes brand = Toyota', () {
      final SmartQuery query = SmartQuery.parse('تويوتا');
      expect(query.valuesOf(SearchFieldKind.brand), <String>['Toyota']);
      expect(describeSteps(query), 'brand.ilike.%Toyota%');
    });

    test('«كامري» becomes model = Camry, not a brand', () {
      final SmartQuery query = SmartQuery.parse('كامري');
      expect(query.valuesOf(SearchFieldKind.model), <String>['Camry']);
      expect(query.hasBrand, isFalse);
      expect(describeSteps(query), 'model.ilike.%Camry%');
    });

    test('«2022» becomes year = 2022', () {
      final SmartQuery query = SmartQuery.parse('2022');
      expect(query.valuesOf(SearchFieldKind.year), <String>['2022']);
      expect(describeSteps(query), 'year.eq.2022');
    });

    test('«بغداد» is a location, not a brand', () {
      final SmartQuery query = SmartQuery.parse('بغداد');
      expect(query.valuesOf(SearchFieldKind.brand), isEmpty);
      expect(query.freeTokens, <String>['بغداد']);
      // الموقع يُطابَق على المدينة والمحافظة والمحافظة القديمة والعنوان.
      expect(query.orClause, contains('city.ilike.%بغداد%'));
      expect(query.orClause, contains('province.ilike.%بغداد%'));
      expect(query.orClause, contains('governorate.ilike.%بغداد%'));
    });

    test('«أوتوماتيك» matches gearbox by prefix, not equality', () {
      final SmartQuery query = SmartQuery.parse('أوتوماتيك');
      expect(query.valuesOf(SearchFieldKind.transmission), <String>['أوتوماتيك']);
      // البادئة ضرورية: كل القيم المخزَّنة «أوتوماتيك N سرعات».
      expect(describeSteps(query), 'transmission.ilike.%أوتوماتيك%');
    });

    test('«بنزين» becomes fuel', () {
      final SmartQuery query = SmartQuery.parse('بنزين');
      expect(query.valuesOf(SearchFieldKind.fuel), <String>['بنزين']);
      expect(describeSteps(query), 'fuel.ilike.%بنزين%');
    });

    test('«نيسان 2022» keeps brand and year as SEPARATE conditions', () {
      final SmartQuery query = SmartQuery.parse('نيسان 2022');
      expect(query.valuesOf(SearchFieldKind.brand), <String>['Nissan']);
      expect(query.valuesOf(SearchFieldKind.year), <String>['2022']);
      // بارامترات منفصلة لا `or` واحد: داخل `or` واحد يقرأ PostgREST هذا
      // «نيسان **أو** 2022» فيعيد كل نيسان مهما كانت سنته.
      expect(conditionCount(query), 2);
      expect(
        describeSteps(query),
        'brand.ilike.%Nissan% AND year.eq.2022',
      );
    });

    test('«تويوتا كامري بغداد» keeps three SEPARATE conditions', () {
      final SmartQuery query = SmartQuery.parse('تويوتا كامري بغداد');
      expect(query.valuesOf(SearchFieldKind.brand), <String>['Toyota']);
      expect(query.valuesOf(SearchFieldKind.model), <String>['Camry']);
      expect(query.freeTokens, <String>['بغداد']);
      expect(query.describe, contains('brand=Toyota'));
      expect(query.describe, contains('model=Camry'));
      expect(query.describe, contains('location=بغداد'));
      expect(conditionCount(query), 3);
      expect(
        describeSteps(query),
        'brand.ilike.%Toyota% AND model.ilike.%Camry% AND '
        'or(city.ilike.%بغداد%|province.ilike.%بغداد%|'
        'governorate.ilike.%بغداد%|title.ilike.%بغداد%)',
      );
    });

    test('two brands become ONE or-group, not two conditions', () {
      final SmartQuery query = SmartQuery.parse('نيسان تويوتا');
      expect(query.valuesOf(SearchFieldKind.brand),
          <String>['Nissan', 'Toyota']);
      // نفس العمود مرتين: البدائل تُدمج بـOR داخل المجموعة الواحدة.
      expect(conditionCount(query), 1);
      expect(
        describeSteps(query),
        'or(brand.ilike.%Nissan%|brand.ilike.%Toyota%)',
      );
    });

    test('Latin input works too, and case does not matter', () {
      expect(SmartQuery.parse('toyota').valuesOf(SearchFieldKind.brand),
          <String>['Toyota']);
      expect(SmartQuery.parse('TOYOTA').valuesOf(SearchFieldKind.brand),
          <String>['Toyota']);
      expect(SmartQuery.parse('Camry').valuesOf(SearchFieldKind.model),
          <String>['Camry']);
      expect(SmartQuery.parse('PETROL').valuesOf(SearchFieldKind.fuel),
          <String>['بنزين']);
      expect(SmartQuery.parse('baghdad').freeTokens, <String>['baghdad']);
    });

    test('Arabic spelling variants all reach the same brand', () {
      for (final String variant in <String>['نيسان', 'نيسن', 'نيسون', 'Nissan']) {
        expect(SmartQuery.parse(variant).valuesOf(SearchFieldKind.brand),
            <String>['Nissan'],
            reason: 'variant $variant');
      }
    });

    test('Arabic-Indic digits are read as a year', () {
      expect(SmartQuery.parse('٢٠٢٢').valuesOf(SearchFieldKind.year),
          <String>['2022']);
    });

    test('an empty query yields no clause', () {
      expect(SmartQuery.parse('').isEmpty, isTrue);
      expect(SmartQuery.parse('   ').orClause, isNull);
      expect(SmartQuery.parse('').orClause, isNull);
    });
  });

  group('أمان نمط PostgREST', () {
    test('a comma from the user is not read as a clause separator', () {
      // الفاصلة داخل كلمة واحدة يجب أن تُحذف، لا أن تفصل بين شرطين.
      expect(describeSteps(SmartQuery.parse('a,b')), describeSteps(SmartQuery.parse('ab')));
      expect(describeSteps(SmartQuery.parse('نيسان,')), 'brand.ilike.%Nissan%');
    });

    test('parentheses and wildcards cannot rewrite the clause', () {
      // `)` كان سيقفل جملة or() في أي موضع.
      expect(describeSteps(SmartQuery.parse('x(y)')), describeSteps(SmartQuery.parse('xy')));
      expect(
          describeSteps(SmartQuery.parse('%wild%')), describeSteps(SmartQuery.parse('wild')));
    });

    test('car filters strip the same characters', () {
      final CarSearchFilters filters = CarSearchFilters()..brand = 'To,yota)';
      expect(filters.plan.steps.single.toString(), 'QueryStep.brand.ilike.%Toyota%');
    });
  });

  group('خطة الفلاتر المتقدمة', () {
    test('empty filters produce an empty plan', () {
      expect(CarSearchFilters().plan.isEmpty, isTrue);
      expect(CarSearchFilters().isEmpty, isTrue);
    });

    test('every field reaches the plan', () {
      final CarSearchFilters filters = CarSearchFilters()
        ..brand = 'Toyota'
        ..model = 'Camry'
        ..fromYear = '2020'
        ..toYear = '2023'
        ..minPrice = '5000'
        ..maxPrice = '15000'
        ..province = 'بغداد'
        ..fuel = 'بنزين'
        ..transmission = 'أوتوماتيك'
        ..maxMileage = '80000';
      final FilterPlan plan = filters.plan;

      // كل حقل في خطوة مستقلة حتى تُدمج كلها بـAND، والمحافظة وحدها مجموعة
      // بدائل لعمودين (province + governorate القديمان).
      expect(plan.steps.length, 5);
      final String joined = plan.steps.map((QueryStep s) => s.toString()).join(' | ');
      expect(joined, contains('brand.ilike.%Toyota%'));
      expect(joined, contains('model.ilike.%Camry%'));
      expect(joined, contains('fuel.ilike.%بنزين%'));
      expect(joined, contains('transmission.ilike.%أوتوماتيك%'));
      expect(joined, contains('province.ilike.%بغداد%'));
      expect(joined, contains('governorate.ilike.%بغداد%'));
      expect(plan.lowYear, 2020);
      expect(plan.highYear, 2023);
      expect(plan.lowPrice, 5000);
      expect(plan.highPrice, 15000);
      expect(plan.maxMileage, 80000);
      expect(filters.isNotEmpty, isTrue);
    });

    test('a non-numeric year is ignored rather than breaking the query', () {
      final CarSearchFilters filters = CarSearchFilters()
        ..fromYear = 'السنة'
        ..toYear = '2023';
      final FilterPlan plan = filters.plan;
      expect(plan.lowYear, isNull);
      expect(plan.highYear, 2023);
    });

    test('clear resets every field', () {
      final CarSearchFilters filters = CarSearchFilters()..fuel = 'بنزين';
      filters.clear();
      expect(filters.isEmpty, isTrue);
    });
  });

  group('الاقتراحات', () {
    final SearchVocabulary vocabulary = vocabularyFromRows(
      const <Map<String, dynamic>>[
        <String, dynamic>{'brand': 'Nissan', 'model': 'Patrol', 'city': 'بغداد', 'province': 'بغداد', 'fuel': 'بنزين', 'transmission': 'أوتوماتيك 6 سرعات', 'body_type': 'SUV'},
        <String, dynamic>{'brand': 'Nissan', 'model': 'Sunny', 'city': 'البصرة', 'province': 'البصرة', 'fuel': 'ديزل', 'transmission': 'أوتوماتيك', 'body_type': 'سيدان'},
        <String, dynamic>{'brand': 'Toyota', 'model': 'Camry', 'city': 'أربيل', 'province': 'أربيل', 'fuel': 'بنزين', 'transmission': 'أوتوماتيك 8 سرعات', 'body_type': 'سيدان'},
        <String, dynamic>{'brand': 'Toyota', 'model': 'Corolla', 'city': 'النجف', 'province': 'النجف', 'fuel': 'هجين', 'transmission': 'أوتوماتيك', 'body_type': 'سيدان'},
      ],
    );

    test('«نيس» suggests the brand and its models that exist', () {
      final List<String> displays =
          vocabulary.suggest('نيس').map((SearchSuggestion s) => s.display).toList();
      expect(displays, contains('Nissan'));
      expect(displays, contains('Nissan Patrol'));
      expect(displays, contains('Nissan Sunny'));
    });

    test('«توي» suggests Toyota and its models', () {
      final List<String> displays = vocabulary
          .suggest('توي')
          .map((SearchSuggestion s) => s.display)
          .toList();
      expect(displays, contains('Toyota'));
      expect(displays, contains('Toyota Camry'));
      expect(displays, contains('Toyota Corolla'));
    });

    test('Arabic brand text still finds the Latin brand', () {
      final List<String> displays =
          vocabulary.suggest('نيسان').map((SearchSuggestion s) => s.display).toList();
      expect(displays.first, 'Nissan');
    });

    test('«بغداد» suggests the city', () {
      final List<String> displays =
          vocabulary.suggest('بغد').map((SearchSuggestion s) => s.display).toList();
      expect(displays, contains('بغداد'));
    });

    test('an empty vocabulary still suggests from the built-in dictionary', () {
      // القاعدة قد تكون غير متاحة؛ القاموس المدمج يعمل بلا شبكة، والاقتراح
      // منه صحيح وإن لم توجد سيارة بهذا الماركة. المهم ألّا يرمي استثناء.
      final SearchVocabulary empty =
          vocabularyFromRows(const <Map<String, dynamic>>[]);
      expect(empty.isEmpty, isTrue);
      expect(empty.suggest(''), isEmpty);
      expect(
        empty.suggest('نيس').map((SearchSuggestion s) => s.display),
        <String>['Nissan'],
      );
      expect(empty.suggest('xyz'), isEmpty);
    });

    test('the suggestion list is capped', () {
      expect(vocabulary.suggest('تو').length, lessThanOrEqualTo(8));
    });

    test('null and blank cells are skipped', () {
      final SearchVocabulary sparse = vocabularyFromRows(
        const <Map<String, dynamic>>[
          <String, dynamic>{'brand': null, 'model': '', 'city': '  '},
          <String, dynamic>{'brand': 'Kia', 'model': null},
        ],
      );
      expect(sparse.brands, <String>['Kia']);
      expect(sparse.models, isEmpty);
      expect(sparse.cities, isEmpty);
      expect(sparse.composites, isEmpty);
    });
  });
}