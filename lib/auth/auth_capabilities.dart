import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

class AuthCapabilities {
  const AuthCapabilities(
      {required this.phoneOtpEnabled, required this.emailEnabled});
  final bool phoneOtpEnabled, emailEnabled;
  factory AuthCapabilities.fromSettings(Map<String, dynamic> settings) {
    final external = settings['external'];
    if (external is! Map ||
        external['phone'] is! bool ||
        external['email'] is! bool) {
      throw const FormatException('Missing public auth capability flags');
    }
    return AuthCapabilities(
        phoneOtpEnabled: external['phone'] as bool,
        emailEnabled: external['email'] as bool);
  }
}

class AuthCapabilitiesResult {
  const AuthCapabilitiesResult.ready(this.value);
  const AuthCapabilitiesResult.failed() : value = null;
  final AuthCapabilities? value;
}

typedef AuthCapabilitiesLoader = Future<AuthCapabilitiesResult> Function();

/// Public capability read only: this endpoint does not send SMS or create users.
Future<AuthCapabilitiesResult> fetchAuthCapabilities(
    {required String baseUrl,
    required String publishableKey,
    http.Client? client}) async {
  final transport = client ?? http.Client();
  try {
    final response = await transport.get(Uri.parse('$baseUrl/auth/v1/settings'),
        headers: {
          'apikey': publishableKey
        }).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      return const AuthCapabilitiesResult.failed();
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) {
      return const AuthCapabilitiesResult.failed();
    }
    return AuthCapabilitiesResult.ready(AuthCapabilities.fromSettings(data));
  } catch (_) {
    return const AuthCapabilitiesResult.failed();
  } finally {
    if (client == null) transport.close();
  }
}

/// Allows an application host or an isolated test to supply the capability read.
class AuthCapabilitiesScope extends InheritedWidget {
  const AuthCapabilitiesScope(
      {super.key, required this.loader, required super.child});
  final AuthCapabilitiesLoader loader;
  static AuthCapabilitiesLoader? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AuthCapabilitiesScope>()?.loader;
  @override
  bool updateShouldNotify(AuthCapabilitiesScope oldWidget) =>
      oldWidget.loader != loader;
}
