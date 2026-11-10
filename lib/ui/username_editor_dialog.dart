import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import '../main.dart' show backendAuthSession;
import 'account_feed_state.dart';

/// Keeps the identifier draft until a save succeeds in its original session.
class UsernameEditorDialog extends StatefulWidget {
  const UsernameEditorDialog({super.key, required this.onSave});
  final Future<void> Function(String username) onSave;
  @override
  State<UsernameEditorDialog> createState() => _UsernameEditorDialogState();
}

class _UsernameEditorDialogState extends State<UsernameEditorDialog>
    with AccountFeedState<UsernameEditorDialog> {
  final _controller = TextEditingController();
  final _form = GlobalKey<FormState>();
  late final String? _account = backendAuthSession.user?.id;
  late final int _openedEpoch;
  static final _valid = RegExp(r'^[a-z0-9_]{3,24}$');
  bool _sending = false;
  String? _error;
  bool get _active => accountMatches(_account, _openedEpoch);
  @override
  void initState() {
    super.initState();
    _openedEpoch = accountEpoch;
  }

  @override
  void reloadAccountFeed() {
    _error = 'ui_vehicle_session_changed';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_sending || !_active || !_form.currentState!.validate()) return;
    final normalized = _controller.text.trim().toLowerCase();
    FocusScope.of(context).unfocus();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.onSave(normalized).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (!_active) throw StateError('Username session changed');
      setState(() => _sending = false);
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            _active ? 'ui_username_save_failed' : 'ui_vehicle_session_changed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: !_sending,
      child: Directionality(
        textDirection: appLocale.direction,
        child: AlertDialog(
          scrollable: true,
          title: Text(t('account_username_login'),
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
          content: SizedBox(
              width: 440,
              child: Form(
                  key: _form,
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                            label: t('account_username_login'),
                            child: TextFormField(
                              key: const ValueKey('username_editor_input'),
                              controller: _controller,
                              enabled: !_sending && _active,
                              autocorrect: false,
                              enableSuggestions: false,
                              textDirection: TextDirection.ltr,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _save(),
                              autovalidateMode:
                                  AutovalidateMode.onUserInteraction,
                              validator: (value) => _valid.hasMatch(
                                      (value ?? '').trim().toLowerCase())
                                  ? null
                                  : t('login_username_rule'),
                              onChanged: (_) {
                                if (_error != null) {
                                  setState(() => _error = null);
                                }
                              },
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontSize: 14),
                              decoration: InputDecoration(
                                  hintText: t('login_username_example')),
                            )),
                        const SizedBox(height: 8),
                        Text(t('misc_username_rule'),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Semantics(
                              liveRegion: true,
                              child: Text(t(_error!),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: scheme.error))),
                        ],
                      ]))),
          actions: [
            TextButton(
                onPressed: _sending ? null : () => Navigator.pop(context),
                child: Text(t('common_cancel'))),
            FilledButton(
                onPressed: _sending || !_active ? null : _save,
                child: _sending
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: scheme.onPrimary))
                    : Text(t('common_save'))),
          ],
        ),
      ),
    );
  }
}
