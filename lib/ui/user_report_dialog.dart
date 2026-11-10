import 'package:flutter/material.dart';

import '../backend_api.dart';
import '../l10n/app_delegates.dart';
import '../l10n/app_locale.dart';
import '../main.dart' show backendApi, backendAuthSession;
import '../submission_id.dart';
import 'account_feed_state.dart';

class UserReportDialog extends StatefulWidget {
  const UserReportDialog({
    super.key,
    required this.offerId,
    required this.reportedUserId,
  });

  final String offerId;
  final String reportedUserId;

  @override
  State<UserReportDialog> createState() => _UserReportDialogState();
}

class _UserReportDialogState extends State<UserReportDialog>
    with AccountFeedState<UserReportDialog> {
  final _reportId = newSubmissionId();
  final _details = TextEditingController();
  late final String? _accountId = backendAuthSession.user?.id;
  late final int _openedEpoch;
  String _reason = 'harassment';
  String? _error;
  bool _sending = false;

  bool get _activeSession => accountMatches(_accountId, _openedEpoch);

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
    _details.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reporter = backendAuthSession.user;
    if (_sending ||
        reporter == null ||
        reporter.id != _accountId ||
        !_activeSession ||
        reporter.id == widget.reportedUserId ||
        widget.offerId.isEmpty) {
      setState(() => _error = 'ui_vehicle_session_changed');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await backendApi.post('safety/reports', body: {
        'id': _reportId,
        'reported_user_id': widget.reportedUserId,
        'offer_id': widget.offerId,
        'reason': _reason,
        'details': _details.text.trim(),
      });
      final created = response is Map ? response['data'] : null;
      if (created is! Map ||
          created['id']?.toString() != _reportId) {
        throw StateError('Report was not acknowledged');
      }
      if (!mounted || !_activeSession) return;
      Navigator.pop(context, true);
    } on BackendApiException {
      if (!mounted || !_activeSession) return;
      setState(() {
        _sending = false;
        _error = 'ugc_report_send_failed';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = !_activeSession
            ? 'ui_vehicle_session_changed'
            : 'ugc_report_send_failed';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return PopScope(
      canPop: !_sending,
      child: Directionality(
        textDirection: appLocale.direction,
        child: AlertDialog(
          scrollable: true,
          title: Text(t('ugc_report_user_title')),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RadioGroup<String>(
                  groupValue: _reason,
                  onChanged: (value) {
                    if (!_sending && _activeSession && value != null) {
                      setState(() {
                        _reason = value;
                        _error = null;
                      });
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final reason in [
                        'harassment',
                        'hate_speech',
                        'sexual_content',
                        'spam',
                        'fraud',
                        'other',
                      ])
                        RadioListTile<String>(
                          value: reason,
                          enabled: !_sending && _activeSession,
                          title: Text(t('ugc_report_reason_$reason')),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _details,
                  maxLength: 2000,
                  minLines: 2,
                  maxLines: 5,
                  enabled: !_sending && _activeSession,
                  textDirection: appLocale.direction,
                  decoration: InputDecoration(
                    labelText: t('ugc_report_details'),
                    border: const OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    t(_error!),
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: _sending || !_activeSession ? null : _submit,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t('report_submit')),
            ),
          ],
        ),
      ),
    );
  }
}
