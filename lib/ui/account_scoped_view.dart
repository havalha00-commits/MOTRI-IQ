import 'package:flutter/material.dart';
import '../design/app_icons.dart';
import '../l10n/app_delegates.dart';
import '../l10n/app_locale.dart';
import 'account_feed_state.dart';
import 'app_state_panel.dart';

/// A private preview belongs to the session that opened it. Returning to the
/// same account requires opening a fresh preview from the refreshed parent.
class AccountScopedView extends StatefulWidget {
  const AccountScopedView(
      {super.key, required this.accountId, required this.child});
  final String accountId;
  final Widget child;
  @override
  State<AccountScopedView> createState() => _AccountScopedViewState();
}

class _AccountScopedViewState extends State<AccountScopedView>
    with AccountFeedState<AccountScopedView> {
  @override
  void reloadAccountFeed() {}

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    if (accountMatches(widget.accountId, 0)) return widget.child;
    return Scaffold(
      key: const ValueKey('account_scoped_view_expired'),
      appBar: AppBar(),
      body: AppStateView(
          title: t('ui_vehicle_session_changed'), icon: AppIcons.locked),
    );
  }
}
