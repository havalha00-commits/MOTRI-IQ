import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('G10.57 Home first-frame local test isolation', () {
    late String source;

    setUpAll(() {
      source = File('lib/main.dart').readAsStringSync();
    });

    test('guarded supabase getter remains fail-fast in local test mode', () {
      expect(source, contains('SupabaseClient get supabase {'));
      expect(
          source,
          contains(
              "throw StateError('Supabase is disabled in M1E local test mode');"));
      expect(source, contains('if (!supabaseInitialized) {'));
    });
  });
}
