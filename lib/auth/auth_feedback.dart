import 'dart:async';
import 'dart:io';
import 'package:motri_iq/auth/backend_auth_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Translate stable error codes rather than exposing server diagnostics.
String authFeedbackKey(Object error, {String fallback = 'ui_auth_failed'}) {
  if (error is SocketException ||
      error is TimeoutException ||
      error is AuthRetryableFetchException) {
    return 'ui_auth_network';
  }
  if (error is FunctionException) {
    if (error.status == 429) return 'ui_auth_rate_limit';
    if (error.status == 0) return 'ui_auth_network';
    if (error.details is Map && (error.details as Map)['code'] is String) {
      return authFeedbackKey(
          AuthException('', code: (error.details as Map)['code'] as String),
          fallback: fallback);
    }
    return fallback;
  }
  if (error is AuthSessionException) {
    if (error.statusCode == 429) return 'ui_auth_rate_limit';
    return authFeedbackKey(
      AuthException('', code: error.message),
      fallback: fallback,
    );
  }
  if (error is AuthException) {
    if (error.statusCode == '429') return 'ui_auth_rate_limit';
    return switch (error.code) {
      'invalid_credentials' => 'login_wrong_credentials',
      'email_not_confirmed' => 'ui_auth_confirm_email',
      'user_already_exists' || 'email_exists' => 'ui_auth_account_exists',
      'weak_password' => 'ui_auth_password_rejected',
      'otp_expired' => 'ui_auth_otp_expired',
      'over_request_rate_limit' ||
      'over_email_send_rate_limit' ||
      'over_sms_send_rate_limit' =>
        'ui_auth_rate_limit',
      _ => fallback,
    };
  }
  return fallback;
}

bool validAuthEmail(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim());

/// Accept pasted SMS digits in Arabic/Persian while rejecting extra characters.
String? normalizedOtpCode(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    if (rune >= 0x0660 && rune <= 0x0669) {
      out.writeCharCode(0x30 + rune - 0x0660);
    } else if (rune >= 0x06f0 && rune <= 0x06f9) {
      out.writeCharCode(0x30 + rune - 0x06f0);
    } else if (rune == 0x200e ||
        rune == 0x200f ||
        RegExp(r'\s').hasMatch(String.fromCharCode(rune))) {
      continue;
    } else {
      out.writeCharCode(rune);
    }
  }
  final value = out.toString();
  return RegExp(r'^[0-9]{6}$').hasMatch(value) ? value : null;
}
