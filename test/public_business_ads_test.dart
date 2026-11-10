import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/main.dart';

void main() {
  test('guest public-ad feed accepts a successful empty list', () async {
    final previousApi = backendApi;
    final api = BackendApi(
      baseUrl: 'https://backend.test',
      backendOnly: true,
      backendAccessTokenAsync: () async {
        throw StateError('guest ad reads must not restore a session');
      },
      client: MockClient((request) async {
        expect(request.url.path, '/api/business-ads/active');
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response(
          jsonEncode({'success': true, 'data': <dynamic>[]}),
          200,
        );
      }),
    );
    backendApi = api;
    addTearDown(() {
      backendApi = previousApi;
      api.close();
    });

    expect(await loadActiveBusinessAds(), isEmpty);
  });
}
