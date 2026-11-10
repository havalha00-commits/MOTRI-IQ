import 'package:flutter/material.dart';
import '../main.dart' show backendApi, backendAuthSession;
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import '../submission_id.dart';
import 'form_section.dart';
import 'content_direction.dart';
import 'account_feed_state.dart';

class VehicleOfferDialog extends StatefulWidget {
  const VehicleOfferDialog(
      {super.key,
      required this.carId,
      required this.sellerId,
      required this.carTitle,
      required this.originalPrice});
  final String carId, sellerId, carTitle, originalPrice;
  @override
  State<VehicleOfferDialog> createState() => _VehicleOfferDialogState();
}

class _VehicleOfferDialogState extends State<VehicleOfferDialog>
    with AccountFeedState<VehicleOfferDialog> {
  final _amount = TextEditingController(), _message = TextEditingController();
  String? get _currentUserId => backendAuthSession.user?.id;
  late final String? _buyer = _currentUserId;
  bool get _activeSession =>
      backendAuthSession.isAuthenticated &&
      (_buyer == null || _currentUserId == _buyer);

  @override
  void reloadAccountFeed() {
    _error = 'ui_vehicle_session_changed';
  }

  final _id = newSubmissionId();
  bool _sending = false;
  String? _error;
  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    final amount = parseFormDecimal(_amount.text);
    String? error;
    if (_buyer == null || !_activeSession) {
      error = 'ui_vehicle_session_changed';
    } else if (widget.sellerId == _buyer) {
      error = 'req_cannot_price';
    } else if (widget.sellerId.isEmpty || widget.carId.isEmpty) {
      error = 'ad_cannot_seller';
    } else if (amount == null || amount <= 0) {
      error = 'req_price_positive';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final payload = <String, dynamic>{
      'id': _id,
      'car_id': widget.carId,
      'car_title': widget.carTitle,
      'original_price': parseFormDecimal(widget.originalPrice),
      'buyer_id': _buyer,
      'seller_id': widget.sellerId,
      'offer_price': amount,
      'message': _message.text.trim().isEmpty ? null : _message.text.trim()
    };
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final response = await backendApi.post('offers', body: payload);
      final created = response is Map ? response['data'] : null;
      if (created is! Map ||
          created['id']?.toString() != _id ||
          !_activeSession) {
        throw StateError('Offer acknowledgement missing');
      }
      if (!mounted) return;
      setState(() => _sending = false);
      Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _activeSession
              ? 'ui_vehicle_offer_unconfirmed'
              : 'ui_vehicle_session_changed';
        });
      }
    }
  }

  Widget _input(TextEditingController controller, String label,
      {bool amount = false}) {
    final theme = Theme.of(context);
    Widget input(TextDirection direction) => TextField(
          key: ValueKey(amount ? 'offer_amount' : 'offer_message'),
          controller: controller,
          enabled: !_sending && _activeSession,
          maxLines: amount ? 1 : 3,
          maxLength: amount ? null : 2000,
          textDirection: direction,
          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          keyboardType: amount
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.multiline,
          textInputAction:
              amount ? TextInputAction.next : TextInputAction.newline,
          decoration: const InputDecoration(counterText: ''),
        );
    return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ExcludeSemantics(
              child: Text(t(label),
                  style: theme.textTheme.labelMedium?.copyWith(fontSize: 13))),
          const SizedBox(height: 6),
          Semantics(
              label: t(label),
              child: amount
                  ? input(TextDirection.ltr)
                  : ContentDirectionBuilder(
                      controller: controller,
                      builder: (_, direction) => input(direction))),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
        canPop: !_sending,
        child: Directionality(
            textDirection: appLocale.direction,
            child: AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              scrollable: true,
              title: Text(t('offer_your_price'),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700)),
              content: SizedBox(
                  width: 520,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                            t('ui_asking_price')
                                .replaceAll('{price}', widget.originalPrice),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                        const SizedBox(height: 20),
                        _input(_amount, 'offer_usd', amount: true),
                        _input(_message, 'field_optional_seller_msg'),
                      ])),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_error != null)
                            Semantics(
                                liveRegion: true,
                                child: Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: Text(t(_error!),
                                        style:
                                            TextStyle(color: scheme.error)))),
                          Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                    onPressed: _sending
                                        ? null
                                        : () => Navigator.pop(context),
                                    child: Text(t('common_cancel'))),
                                FilledButton(
                                    onPressed: _sending || !_activeSession
                                        ? null
                                        : _submit,
                                    child: _sending
                                        ? SizedBox.square(
                                            dimension: 20,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: scheme.onPrimary))
                                        : Text(t('req_send_offer'))),
                              ]),
                        ])),
              ],
            )));
  }
}
