import 'package:flutter/material.dart';
import '../main.dart' show backendApi, backendAuthSession;
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import 'account_feed_state.dart';

class VehicleSaleDialog extends StatefulWidget {
  const VehicleSaleDialog(
      {super.key, required this.carId, required this.ownerId});
  final String carId, ownerId;
  @override
  State<VehicleSaleDialog> createState() => _VehicleSaleDialogState();
}

class _VehicleSaleDialogState extends State<VehicleSaleDialog>
    with AccountFeedState<VehicleSaleDialog> {
  String? get _currentUserId => backendAuthSession.user?.id;
  late final String? _account = _currentUserId;
  bool get _activeSession =>
      backendAuthSession.isAuthenticated &&
      (_account == null || _currentUserId == _account);

  @override
  void reloadAccountFeed() {
    _error = 'ui_vehicle_session_changed';
  }

  bool _sending = false;
  String? _error;

  Future<void> _submit() async {
    if (_sending) return;
    if (_account == null ||
        _account != widget.ownerId ||
        !_activeSession ||
        widget.carId.isEmpty) {
      setState(() => _error = 'ui_vehicle_session_changed');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await backendApi.patch(
        'cars/my/${widget.carId}/status',
        body: {'status': 'sold'},
      );
      final updated = response is Map ? response['data'] : null;
      if (!mounted) return;
      if (!_activeSession ||
          updated is! Map ||
          updated['id']?.toString() != widget.carId ||
          updated['status'] != 'sold') {
        throw StateError('Sale status not acknowledged');
      }
      setState(() => _sending = false);
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = !_activeSession
              ? 'ui_vehicle_session_changed'
              : 'ui_vehicle_sale_failed';
        });
      }
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
          title: Text(t('ad_confirm_sale')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('ad_ask_sold')),
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
          actions: [
            TextButton(
              onPressed: _sending ? null : () => Navigator.pop(context, false),
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
                  : Text(t('ad_status_yes_sold')),
            ),
          ],
        ),
      ),
    );
  }
}
