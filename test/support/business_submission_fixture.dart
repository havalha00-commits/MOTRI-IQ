import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/backend_api.dart';

const businessOwner = '00000000-0000-4000-8000-000000000001';
const businessPackage = '00000000-0000-4000-8000-000000000002';

class BusinessFixture {
  final requests = <http.Request>[], uploads = <http.Request>[];
  final ads = <String, Map<String, dynamic>>{},
      orders = <String, Map<String, dynamic>>{};
  String? failTable, emptyAck, wrongAck;
  int failUploadAt = 0;
  bool failPackages = false, emptyPackages = false;
  Completer<void>? packageGate;
  Completer<void>? uploadGate, adGate, orderGate;
  String authId = businessOwner;
  SupabaseClient get client => Supabase.instance.client;
  late BackendApi api;
  List<http.Request> writes(String table) {
    if (table == 'business_ad_orders') {
      return [];
    }
    return requests.where((r) {
      final body = jsonDecode(r.body);
      return r.url.path.endsWith('/business-ads/submissions') &&
          body['ad_id'] is String;
    }).toList();
  }
  Future<void> initialize() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
        url: 'https://example.supabase.co',
        publishableKey: 'fixture',
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
        httpClient: MockClient((r) async {
          Object? body = [];
          var status = 200;
          if (r.url.path == '/auth/v1/token') {
            final token = base64Url
                .encode(utf8.encode(jsonEncode({
                  'sub': authId,
                  'role': 'authenticated',
                  'exp': DateTime.now()
                          .add(const Duration(hours: 1))
                          .millisecondsSinceEpoch ~/
                      1000
                })))
                .replaceAll('=', '');
            body = {
              'access_token':
                  'eyJhbGciOiJIUzI1NiJ9.$token.${base64Url.encode(List.filled(32, 0)).replaceAll('=', '')}',
              'refresh_token': 'fixture',
              'token_type': 'bearer',
              'expires_in': 3600,
              'user': {
                'id': authId,
                'aud': 'authenticated',
                'role': 'authenticated',
                'email': 'fixture@example.com',
                'created_at': '2026-01-01T00:00:00Z'
              }
            };
          } else if (r.url.path == '/auth/v1/logout') {
            body = {};
          }
          return http.Response(jsonEncode(body), status,
              request: r,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }));
    api = BackendApi(
      baseUrl: 'https://backend.example.test',
      accessToken: () => client.auth.currentSession?.accessToken,
      client: MockClient((r) async {
        Object? body;
        var status = 200;
        if (r.url.path.endsWith('/ugc/acceptance')) {
          body = {
            'success': true,
            'data': {'accepted': true, 'policy_version': '2026-11-05'}
          };
        } else if (r.url.path.endsWith('/business-ads/packages')) {
          await packageGate?.future;
          if (failPackages) {
            status = 503;
            body = {'error': 'Failed to load business packages'};
          } else {
            body = {
              'success': true,
              'data': emptyPackages
                  ? []
                  : [
                      {
                        'id': businessPackage,
                        'name': 'Visibility package',
                        'duration_days': 30,
                        'price': 25,
                        'placements': ['Home', 'Business directory'],
                        'features': ['Business profile and contact details'],
                        'is_active': true
                      }
                    ]
            };
          }
        } else if (r.url.path.endsWith('/uploads/object')) {
          uploads.add(r);
          await uploadGate?.future;
          if (failUploadAt == uploads.length) {
            status = 502;
            body = {'error': 'Image upload failed'};
          } else {
            final bucket = r.url.queryParameters['bucket'];
            final path = r.url.queryParameters['path']!;
            body = {
              'success': true,
              'data': {
                'public_url':
                    'https://example.supabase.co/storage/v1/object/public/$bucket/$path'
              }
            };
          }
        } else if (r.url.path.endsWith('/business-ads/submissions')) {
          requests.add(r);
          final payload = Map<String, dynamic>.from(jsonDecode(r.body));
          await adGate?.future;
          await orderGate?.future;
          if (failTable != null) {
            status = 503;
            body = {'error': 'Failed to submit business ad'};
          } else {
            final adId = payload['ad_id'] as String;
            ads.putIfAbsent(adId, () => {
                  ...Map<String, dynamic>.from(payload['fields'] as Map),
                  'id': adId,
                  'user_id': authId,
                  'logo_url': payload['logo_url'],
                  'image_urls': payload['image_urls'],
                  'package_id': payload['package_id'],
                  'status': 'pending',
                  'price': 25,
                  'start_at': DateTime.now().toUtc().toIso8601String(),
                  'end_at': DateTime.now()
                      .toUtc()
                      .add(const Duration(days: 30))
                      .toIso8601String(),
                });
            if (emptyAck != null || wrongAck != null) {
              body = {'success': true, 'data': {}};
            } else {
              body = {
                'success': true,
                'data': {'ad_id': adId}
              };
            }
          }
        } else {
          status = 404;
          body = {'error': 'not found'};
        }
        return http.Response(
          jsonEncode(body),
          status,
          request: r,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await signIn();
  }

  Future<void> signIn() => client.auth
      .signInWithPassword(email: 'fixture@example.com', password: 'fixture')
      .then((_) {});
  Future<void> loseBackendSession() async {
    try {
      authId = '00000000-0000-4000-8000-000000000099';
    } catch (_) {}
  }
  void reset() {
    requests.clear();
    uploads.clear();
    ads.clear();
    orders.clear();
    failTable = emptyAck = wrongAck = null;
    failUploadAt = 0;
    uploadGate = adGate = orderGate = null;
    failPackages = emptyPackages = false;
    packageGate = null;
    authId = businessOwner;
  }
}
