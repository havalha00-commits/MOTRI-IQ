import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/widgets.dart';
import '../main.dart' show backendAuthSession, supabaseClientOrNull;

/// Refresh personal feeds on account changes and reject prior-session results.
mixin AccountFeedState<T extends StatefulWidget> on State<T> {
  String? _accountId;
  int _epoch = 0;
  VoidCallback? _accountListener;
  StreamSubscription<AuthState>? _supabaseAuthSubscription;
  int get accountEpoch => _epoch;

  String? _currentAccountId() {
    final backendId = backendAuthSession.user?.id;
    if (backendId != null) return backendId;
    try {
      return supabaseClientOrNull?.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  bool accountMatches(String? id, int epoch) {
    String? current;
    try {
      current = _currentAccountId();
    } catch (_) {
      current = null;
    }
    return mounted &&
        id != null &&
        epoch == _epoch &&
        id == _accountId &&
        current == id;
  }

  void reloadAccountFeed();

  @override
  void initState() {
    super.initState();
    try {
      _accountId = _currentAccountId();
      _accountListener = () {
        _handleAccountChange();
      };
      backendAuthSession.addListener(_accountListener!);
      try {
        _supabaseAuthSubscription =
            supabaseClientOrNull?.auth.onAuthStateChange.listen((_) {
          _handleAccountChange();
        });
      } catch (_) {
        _supabaseAuthSubscription = null;
      }
    } catch (_) {
      _accountListener = null;
    }
  }

  void _handleAccountChange() {
    String? next;
    try {
      next = _currentAccountId();
    } catch (_) {
      next = null;
    }
    if (!mounted || next == _accountId) return;
    setState(() {
      _accountId = next;
      _epoch++;
      reloadAccountFeed();
    });
  }

  @override
  void dispose() {
    final listener = _accountListener;
    if (listener != null) {
      try {
        backendAuthSession.removeListener(listener);
      } catch (_) {}
    }
    _accountListener = null;
    unawaited(_supabaseAuthSubscription?.cancel());
    _supabaseAuthSubscription = null;
    super.dispose();
  }
}
