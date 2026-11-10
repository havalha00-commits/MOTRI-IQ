import 'package:flutter/material.dart';
import '../design/app_icons.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import 'account_feed_state.dart';
import 'account_navigation_tile.dart';

enum MessageHubDestination { activity, messages }

/// Navigation is available while the optional unread count loads or fails.
class MessageHubSheet extends StatefulWidget {
  const MessageHubSheet(
      {super.key, required this.accountId, required this.loadUnread});
  final String accountId;
  final Future<int> Function() loadUnread;
  @override
  State<MessageHubSheet> createState() => _MessageHubSheetState();
}

class _MessageHubSheetState extends State<MessageHubSheet>
    with AccountFeedState<MessageHubSheet> {
  late final int _openedEpoch;
  late Future<int> _count;
  bool _selected = false;
  bool get _active => accountMatches(widget.accountId, _openedEpoch);
  @override
  void initState() {
    super.initState();
    _openedEpoch = accountEpoch;
    _count = _load();
  }

  Future<int> _load() async =>
      await widget.loadUnread().timeout(const Duration(seconds: 20));
  @override
  void reloadAccountFeed() {}
  void _select(MessageHubDestination destination) {
    if (!_active || _selected) return;
    _selected = true;
    Navigator.pop(context, destination);
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final theme = Theme.of(context);
    return Directionality(
      textDirection: appLocale.direction,
      child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(t('account_chat'),
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700))),
                    IconButton(
                        tooltip: MaterialLocalizations.of(context)
                            .closeButtonTooltip,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded)),
                  ]),
                  const SizedBox(height: 8),
                  if (!_active)
                    Semantics(
                        liveRegion: true,
                        child: Text(t('ui_vehicle_session_changed')))
                  else ...[
                    AccountNavigationTile(
                        icon: AppIcons.notifications,
                        title: t('chat_hub_desc'),
                        onTap: () => _select(MessageHubDestination.activity)),
                    FutureBuilder<int>(
                        future: _count,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Semantics(
                                    liveRegion: true,
                                    child: Row(children: [
                                      const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                          child: Text(t('ui_loading_title'),
                                              style:
                                                  theme.textTheme.bodySmall)),
                                    ])));
                          }
                          if (snapshot.hasError) {
                            return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Row(children: [
                                  Expanded(
                                      child: Semantics(
                                          liveRegion: true,
                                          child: Text(
                                              t('ui_unread_unavailable'),
                                              style:
                                                  theme.textTheme.bodySmall))),
                                  IconButton(
                                      tooltip: t('ui_retry'),
                                      onPressed: () {
                                        if (_active) {
                                          setState(() {
                                            _count = _load();
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.refresh_rounded)),
                                ]));
                          }
                          final count = snapshot.data ?? 0;
                          if (count <= 0) return const SizedBox.shrink();
                          return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Semantics(
                                  liveRegion: true,
                                  child: Text(
                                      t('ui_unread_count')
                                          .replaceAll('{count}', '$count'),
                                      style: theme.textTheme.bodySmall)));
                        }),
                    AccountNavigationTile(
                        icon: AppIcons.chat,
                        title: t('chat_messages_title'),
                        onTap: () => _select(MessageHubDestination.messages)),
                  ],
                ]),
          )),
    );
  }
}
