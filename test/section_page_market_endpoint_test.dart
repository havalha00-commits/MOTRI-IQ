import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('G10.58 SectionPage market list endpoint correction', () {
    late String source;
    late String fetchBody;

    setUpAll(() {
      source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _fetch({required bool reset}) async {');
      expect(start, greaterThanOrEqualTo(0), reason: 'SectionPage._fetch must exist');
      // End at the image-preload helper that follows _fetch.
      final end = source.indexOf('/// Preload first image of visible cars only', start);
      expect(end, greaterThan(start), reason: '_fetch boundary marker must exist');
      fetchBody = source.substring(start, end);
    });

    test('market uses GET /api/market/items with limit only (no offset/brand)', () {
      expect(fetchBody, contains("backendApi.get('market/items?limit=\$_pageSize')"));
      expect(fetchBody, contains('Backend GET /api/market/items supports limit only'));
      // Guard against reintroducing market query params in the market branch.
      expect(fetchBody, isNot(contains("backendApi.get('market/items?\$qs')")));
      expect(fetchBody, isNot(contains("backendApi.get('cars?limit=\$_pageSize') isMarket")));
    });

    test('market fetch prevents repeated/scroll pagination requests', () {
      expect(fetchBody, contains('final isMarket = table == \'market_items\';'));
      expect(fetchBody, contains('_hasMore = isMarket ? false : rows.length == _pageSize;'));
      // OnScroll already guards on !_hasMore; market must not append-offset page.
      expect(fetchBody, contains('combined = (reset || isMarket) ? rows : [..._items, ...rows]'));
    });

    test('cars endpoint and pagination params remain unchanged', () {
      expect(fetchBody, contains("final isCars = table == 'cars_public';"));
      expect(fetchBody, contains("final params = <String, String>{"));
      expect(fetchBody, contains("'limit': '\$_pageSize',"));
      expect(fetchBody, contains("'offset': '\$offset',"));
      expect(fetchBody, contains("if (brand != null) params['brand'] = brand;"));
      expect(fetchBody, contains("backendApi.get('cars?\$qs')"));
      expect(fetchBody, contains('_nextOffset = isMarket ? rows.length : offset + rows.length;'));
    });

    test('jobs/table-null path remains empty with no fabricated request', () {
      // _table returns null for Jobs; _fetch returns early with no request.
      final tableStart = source.indexOf('String? get _table {');
      final tableEnd = source.indexOf('/// `_loadingMore`', tableStart);
      expect(tableStart, greaterThanOrEqualTo(0));
      expect(tableEnd, greaterThan(tableStart));
      final tableBody = source.substring(tableStart, tableEnd);
      expect(tableBody, contains("if (widget.title == kSectionMarket) return 'market_items';"));
      expect(tableBody, contains('return null;'));
      expect(tableBody, isNot(contains("'jobs'")));

      expect(fetchBody, contains('if (table == null) {'));
      expect(fetchBody, contains('_items.clear(); _loading = _loadingMore = _hasMore = false;'));
      expect(fetchBody, isNot(contains("backendApi.get('jobs")));
      expect(fetchBody, isNot(contains('/jobs?')));
    });

    test('car-only image preload is not invoked for market rows', () {
      expect(fetchBody, contains('if (isCars) _preloadImages(rows);'));
      expect(fetchBody, isNot(contains('if (isMarket) _preloadImages(rows);')));
    });

    test('parses existing {success,data} response shape', () {
      expect(fetchBody, contains("final data = response['data'];"));
      expect(fetchBody, contains('data is List'));
    });
  });
}
