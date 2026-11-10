import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('G10.62 Phase 3.3 market flow backend-only isolation (local-test)', () {
    late String mainSrc;
    late String marketImagesSrc;
    late String genericDialogSrc;
    late String backendApiSrc;
    late String ugcSrc;

    setUpAll(() {
      mainSrc = File('lib/main.dart').readAsStringSync();
      marketImagesSrc = File('lib/market_images.dart').readAsStringSync();
      genericDialogSrc = File('lib/ui/generic_ad_editor_dialog.dart').readAsStringSync();
      backendApiSrc = File('lib/backend_api.dart').readAsStringSync();
      ugcSrc = File('lib/ui/ugc_policy_consent.dart').readAsStringSync();
    });

    test('global backendApi is backend-only in MOTRI_LOCAL_TEST; Supabase init skipped', () {
      expect(mainSrc, contains("const bool kMotriLocalTest = bool.fromEnvironment('MOTRI_LOCAL_TEST', defaultValue: false);"));
      expect(mainSrc, contains('backendOnly: kMotriLocalTest'));
      expect(mainSrc, contains('if (!kMotriLocalTest) {'));
      expect(mainSrc, contains('await Supabase.initialize'));
    });

    test('BackendApi supports backendOnly and rejects missing backend token in backend-only mode', () {
      expect(backendApiSrc, contains('bool backendOnly = false'));
      expect(backendApiSrc, contains("Backend authentication required"));
      expect(backendApiSrc, contains('backendOnly: backendOnly'));
      expect(backendApiSrc, contains('putBytes'));
    });

    test('home market preview uses backend API (no offset/brand fabrication)', () {
      // Existing home preview loader
      expect(mainSrc, contains("backendApi.get('market/items?limit=5')"));
    });

    test('market listing uses backend /market/items with limit only; no jobs read API fabricated', () {
      expect(mainSrc, contains("backendApi.get('market/items?limit=\$_pageSize')"));
      expect(mainSrc, contains('Backend GET /api/market/items supports limit only'));
      expect(mainSrc, isNot(contains("backendApi.get('jobs")));
      expect(mainSrc, isNot(contains("backendApi.get('/api/jobs")));
    });

    test('add market flow checks backend session in local test (no guarded supabase getter)', () {
      final addStart = mainSrc.indexOf('Future<void> addGenericAd() async {');
      expect(addStart, greaterThanOrEqualTo(0));
      final addEnd = mainSrc.indexOf('void _msg(String message) {', addStart);
      final body = mainSrc.substring(addStart, addEnd);
      expect(body, contains('backendAuthSession.user != null'));
      expect(body, contains('kMotriLocalTest'));
      expect(body, contains('GenericAdEditorDialog(isMarket: widget.title == kSectionMarket)'));
      expect(body, isNot(contains('supabase.auth.currentUser')));
      expect(body, isNot(contains('Supabase.instance')));
    });

    test('market add dialog posts to backend market APIs and uses backend session', () {
      expect(genericDialogSrc, contains("backendApi.post("));
      expect(genericDialogSrc, contains("'market/\${widget.isMarket ? 'items' : 'jobs'}'"));
      expect(genericDialogSrc, contains('backendAuthSession.user?.id'));
      expect(genericDialogSrc, isNot(contains('Supabase.instance')));
      expect(genericDialogSrc, isNot(contains('supabase.auth')));
      expect(genericDialogSrc, isNot(contains('supabase.from')));
      expect(genericDialogSrc, isNot(contains('supabase.storage')));
    });

    test('market image upload uses backend upload API with backendOnly in local test mode', () {
      expect(marketImagesSrc, contains("'market/uploads'"));
      expect(marketImagesSrc, contains("query: {'kind': kind}"));
      expect(marketImagesSrc, contains('backendOnly: kMotriLocalTest'));
      expect(marketImagesSrc, contains('delivery_url') /* backend-controlled ref/path acknowledgement */);
      expect(marketImagesSrc, isNot(contains('supabase.storage')));
      expect(marketImagesSrc, isNot(contains('Supabase.instance')));
    });

    test('market image delivery resolves backend /api/market/images path (no Supabase public URL)', () {
      expect(marketImagesSrc, contains("value.startsWith('/api/market/images/')"));
      expect(marketImagesSrc, contains("uri.path.startsWith('/api/market/images/')"));
      expect(marketImagesSrc, contains('_resolveBackendUrl'));
      expect(marketImagesSrc, contains('backendUrl'));
      expect(marketImagesSrc, isNot(contains('storage/v1/object/public')));
    });

    test('market item details use backend APIs for edit/delete and backend session checks', () {
      expect(marketImagesSrc, contains("backendApi.patch("));
      expect(marketImagesSrc, contains("'market/\${jobs ? 'jobs' : 'items'}/\${widget.item['id']}/images'"));
      expect(marketImagesSrc, contains("backendApi.delete('market/items/\$id')"));
      expect(marketImagesSrc, contains('backendAuthSession.user'));
      expect(marketImagesSrc, isNot(contains('supabase.auth')));
      expect(marketImagesSrc, isNot(contains('supabase.from')));
      expect(marketImagesSrc, isNot(contains('Supabase.instance')));
    });

    test('UGC policy consent uses backend API/session only', () {
      expect(ugcSrc, contains("api.get('ugc/acceptance')"));
      expect(ugcSrc, contains("api.post("));
      expect(ugcSrc, contains("'ugc/acceptance'"));
      expect(ugcSrc, contains('backendAuthSession.user?.id'));
      expect(ugcSrc, isNot(contains('Supabase.instance')));
      expect(ugcSrc, isNot(contains('supabase.')));
    });

    test('no jobs read/list UI endpoints invented', () {
      expect(mainSrc, isNot(contains("backendApi.get('market/jobs")));
      expect(mainSrc, isNot(contains("backendApi.get('jobs")));
      expect(marketImagesSrc, isNot(contains("backendApi.get('market/jobs")));
      expect(marketImagesSrc, isNot(contains("backendApi.get('jobs")));
    });
  });
}
