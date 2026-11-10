import 'package:flutter/material.dart';
import '../backend_api.dart';
import '../main.dart' show backendApi, backendAuthSession;
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import 'account_feed_state.dart';
import '../submission_id.dart';

class VehicleReportDialog extends StatefulWidget {
  const VehicleReportDialog(
      {super.key, required this.carId, required this.sellerId});
  final String carId, sellerId;
  @override
  State<VehicleReportDialog> createState() => _VehicleReportDialogState();
}

class _VehicleReportDialogState extends State<VehicleReportDialog>
    with AccountFeedState<VehicleReportDialog> {
  String? get _currentUserId => backendAuthSession.user?.id;
  late final String? _account = _currentUserId;
  bool get _activeSession =>
      backendAuthSession.isAuthenticated &&
      (_account == null || _currentUserId == _account);

  @override
  void reloadAccountFeed() {
    _error = 'ui_vehicle_session_changed';
  }

  final _id = newSubmissionId();
  String _reason = 'report_bad_info';
  String? _error;
  bool _sending = false;

  Future<void> _submit() async {
    if (_sending) return;
    if (_account == null ||
        !_activeSession ||
        widget.sellerId == _account ||
        widget.carId.isEmpty) {
      setState(() => _error = 'ui_vehicle_session_changed');
      return;
    }
    final payload = {
      'id': _id,
      'car_id': widget.carId,
      'seller_id': widget.sellerId.isEmpty ? null : widget.sellerId,
      'reason': t(_reason),
    };
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await backendApi.post(
        'safety/car-reports',
        body: payload,
      );
      final created = response is Map ? response['data'] : null;
      if (created is! Map || created['id']?.toString() != _id) {
        throw StateError('Report was not acknowledged');
      }
      if (!mounted) return;
      if (!_activeSession) {
        throw StateError('Report account changed');
      }
      setState(() => _sending = false);
      Navigator.pop(context, 'report_received');
    } on BackendApiException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 409 && _activeSession) {
        setState(() => _sending = false);
        Navigator.pop(context, 'report_already');
      } else {
        _failed();
      }
    } catch (_) {
      _failed();
    }
  }

  void _failed() {
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error =
          !_activeSession ? 'ui_vehicle_session_changed' : 'report_send_failed';
    });
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
          title: Text(t('report_ad')),
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
                      for (final key in [
                        'report_bad_info',
                        'report_duplicate',
                        'support_issue_scam',
                        'support_issue_other'
                      ])
                        RadioListTile<String>(
                          value: key,
                          enabled: !_sending && _activeSession,
                          fillColor: WidgetStateProperty.resolveWith((states) {
                            final scheme = Theme.of(context).colorScheme;
                            if (states.contains(WidgetState.disabled)) {
                              return scheme.onSurface.withValues(alpha: .38);
                            }
                            if (states.contains(WidgetState.selected)) {
                              return Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? scheme.onSurface
                                  : scheme.primary;
                            }
                            return scheme.onSurfaceVariant;
                          }),
                          title: Text(t(key)),
                        ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(t(_error!),
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: _sending || !_activeSession ? null : _submit,
              child: _sending
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary))
                  : Text(t('report_submit')),
            ),
          ],
        ),
      ),
    );
  }
}
