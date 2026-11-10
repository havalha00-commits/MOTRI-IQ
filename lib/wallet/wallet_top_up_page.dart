import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/release_channel.dart';
import 'package:motri_iq/ui/account_feed_state.dart';
import 'package:motri_iq/ui/app_state_panel.dart';
import 'package:motri_iq/design/app_icons.dart';

class WalletTopUpPage extends StatefulWidget {
  const WalletTopUpPage({super.key, this.receiptPicker});
  final Future<XFile?> Function()? receiptPicker;

  @override
  // Select before the payment state can initialize backend/payment resources.
  // ignore: no_logic_in_create_state
  State<WalletTopUpPage> createState() => restrictPaidFeatures
      ? PaidFeatureUnavailableState<WalletTopUpPage>()
      : _WalletTopUpPageState();
}

class PaidFeatureUnavailableState<T extends StatefulWidget> extends State<T> {
  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Scaffold(
      appBar: AppBar(title: Text(t('play_paid_unavailable_title'))),
      body: AppStatePanel(
        icon: Icons.info_outline_rounded,
        title: t('play_paid_unavailable_title'),
        message: t('play_paid_unavailable_body'),
      ),
    );
  }
}

class _WalletTopUpPageState extends State<WalletTopUpPage>
    with AccountFeedState<WalletTopUpPage> {
  int? _selectedAmount;
  bool _submitting = false;
  bool _loadingAccount = true, _accountFailed = false, _picking = false;
  Uint8List? _receiptBytes;
  bool _submitted = false;
  String? _kcardAccount;
  XFile? _receiptFile;
  String? _submittedTxId;

  static const List<int> _presetAmounts = [5000, 10000, 25000, 50000, 100000];

  @override
  void reloadAccountFeed() {
    _selectedAmount = null;
    _receiptFile = null;
    _receiptBytes = null;
    _submitted = _submitting = _picking = false;
    _submittedTxId = null;
    _kcardAccount = null;
    _accountFailed = false;
    _loadingAccount = backendAuthSession.isAuthenticated;
    if (_loadingAccount) unawaited(_loadKcardAccount());
  }

  @override
  void initState() {
    super.initState();
    if (backendAuthSession.isAuthenticated) {
      _loadKcardAccount();
    } else {
      _loadingAccount = false;
    }
  }

  Future<void> _loadKcardAccount() async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!mounted || !accountMatches(actor, epoch)) return;
    setState(() {
      _loadingAccount = true;
      _accountFailed = false;
    });
    try {
      final res = await backendApi.get('wallet/settings/kcard_account_number');
      final data = res is Map ? res['data'] : null;
      final value = data is Map ? data['value']?.toString() : null;
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _loadingAccount = false;
          _kcardAccount = value?.trim().isNotEmpty == true ? value!.trim() : null;
        });
      }
    } catch (_) {
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _loadingAccount = false;
          _accountFailed = true;
        });
      }
    }
  }

  Future<void> _pickReceipt() async {
    if (_picking || _submitting) return;
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!mounted || !accountMatches(actor, epoch)) return;
    setState(() {
      _picking = true;
    });
    try {
      final file =
          await (widget.receiptPicker?.call() ??
              ImagePicker().pickImage(
                source: ImageSource.gallery,
                maxWidth: 800,
                maxHeight: 800,
              ));
      if (file == null || !accountMatches(actor, epoch)) return;
      final bytes = await file.readAsBytes();
      if (!mounted || !accountMatches(actor, epoch)) return;
      setState(() {
        _receiptFile = file;
        _receiptBytes = bytes;
      });
    } catch (_) {
      if (mounted && accountMatches(actor, epoch)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(t('wallet_pick_image_failed'))));
      }
    } finally {
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _picking = false;
        });
      }
    }
  }

  String _receiptContentType(String objectKey) {
    final ext = objectKey.split('.').last.toLowerCase();
    if (ext == 'jpg' || ext == 'jpeg') return 'image/jpeg';
    if (ext == 'png') return 'image/png';
    if (ext == 'webp') return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _submitTopUp() async {
    if (_submitted || _submitting ||
        _picking ||
        _loadingAccount ||
        _accountFailed ||
        _kcardAccount == null) {
      return;
    }
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    final amount = _selectedAmount;
    if (amount == null) {
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('wallet_no_amount'),
            textDirection: appLocale.direction,
          ),
        ),
      );
      return;
    }
    if (!backendAuthSession.isAuthenticated) {
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('login_not_logged_in'),
            textDirection: appLocale.direction,
          ),
        ),
      );
      return;
    }
    if (_receiptFile == null) {
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('wallet_pick_receipt'),
            textDirection: appLocale.direction,
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final createRes = await backendApi.post('wallet/topups', body: {
        'amount': amount,
      });
      final createData = createRes is Map ? createRes['data'] : null;
      final txId = createData is Map ? createData['id']?.toString() : null;
      if (txId == null || txId.isEmpty) {
        throw const BackendApiException('Missing transaction id');
      }

      final authRes = await backendApi.post('wallet/topups/$txId/receipt/authorize');
      final authPayload = authRes is Map ? authRes['data'] : null;
      final authorizationId = authPayload is Map ? authPayload['authorizationId']?.toString() : null;
      final objectKey = authPayload is Map ? authPayload['objectKey']?.toString() : null;
      if (authorizationId == null || authorizationId.isEmpty || objectKey == null || objectKey.isEmpty) {
        throw const BackendApiException('Missing upload authorization');
      }

      final bytes = _receiptBytes ?? await _receiptFile!.readAsBytes();
      if (!mounted || !accountMatches(actor, epoch)) return;
      await backendApi.postBytes(
        'wallet/topups/$txId/receipt/upload',
        body: bytes,
        contentType: _receiptContentType(objectKey),
        query: {'authorizationId': authorizationId},
      );
      await backendApi.post('wallet/topups/$txId/receipt', body: {
        'authorizationId': authorizationId,
      });

      if (!mounted || !accountMatches(actor, epoch)) return;
      setState(() {
        _submitted = true;
        _submittedTxId = txId;
        _submitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('wallet_submitted_success'),
            textDirection: appLocale.direction,
          ),
        ),
      );
    } catch (_) {
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t('ui_wallet_submit_failed'),
            textDirection: appLocale.direction,
          ),
        ),
      );
    } finally {
      if (mounted && accountMatches(actor, epoch)) setState(() => _submitting = false);
    }
  }

  Future<void> _confirmAsAdmin() async {
    if (_submitting) return;
    if (!backendAuthSession.isAuthenticated) return;
    setState(() => _submitting = true);
    try {
      final txId = _submittedTxId;
      if (txId == null || txId.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('wallet_no_pending'),
              textDirection: appLocale.direction,
            ),
          ),
        );
        return;
      }

      dynamic rpcResult;
      try {
        rpcResult = await backendApi.post(
          'wallet/decide',
          body: {'id': txId, 'status': 'confirmed'},
        );
      } on BackendApiException catch (e) {
        if (!mounted) return;
        if (e.statusCode == 401) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t('login_not_logged_in'), textDirection: appLocale.direction),
            ),
          );
          return;
        }
        if (e.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(t('ui_admin_only'), textDirection: appLocale.direction),
            ),
          );
          return;
        }
        rethrow;
      }

      if (!mounted) return;

      final Map<String, dynamic> map = rpcResult is Map
          ? Map<String, dynamic>.from(rpcResult)
          : {};
      if (map['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('wallet_admin_confirmed'),
              textDirection: appLocale.direction,
            ),
          ),
        );
        Navigator.of(context).pop();
      } else {
        final reason = map['reason']?.toString();
        final msg = reason == 'not_admin'
            ? t('ui_admin_only')
            : (reason == 'already_decided' ? t('ui_wallet_already_decided') : t('payment_update_failed'));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, textDirection: appLocale.direction),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('payment_update_failed'),
              textDirection: appLocale.direction,
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final loggedIn = backendAuthSession.isAuthenticated;
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_wallet_topup'))),
        body: !loggedIn
            ? AppStateView(
                title: t('login_not_logged_in'),
                icon: AppIcons.locked,
              )
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!_submitted) ...[
                            Text(
                              t('wallet_select_amount'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.textStrong,
                              ),
                              textAlign: TextAlign.start,
                            ),
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.start,
                              children: _presetAmounts.map((amount) {
                                final selected = _selectedAmount == amount;
                                return ChoiceChip(
                                  selected: selected,
                                  onSelected: _submitting || _picking
                                      ? null
                                      : (_) => setState(() {
                                          _selectedAmount = amount;
                                        }),
                                  label: Text(formatIqd(amount), textDirection: TextDirection.ltr),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  showCheckmark: true,
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            _buildPaymentSection(),
                            const SizedBox(height: 24),
                            _buildReceiptSection(),
                            const SizedBox(height: 24),
                            FilledButton(
                              key: const ValueKey('wallet_submit'),
                              onPressed:
                                  _submitting ||
                                      _picking ||
                                      _loadingAccount ||
                                      _accountFailed ||
                                      _kcardAccount == null
                                  ? null
                                  : _submitTopUp,
                              style: FilledButton.styleFrom(
                                backgroundColor: red,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(t('payment_confirm')),
                            ),
                          ] else ...[
                            _buildSubmittedSection(),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t('wallet_payment_method'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: AppColors.textStrong,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t('wallet_kcard'),
            style: TextStyle(
              color: AppColors.textStrong,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingAccount)
            Text(t('ui_loading_title'))
          else if (_accountFailed)
            AppStatePanel(
              title: t('ui_load_error_title'),
              icon: AppIcons.cloudOff,
              isError: true,
              actionLabel: t('ui_retry'),
              onAction: _loadKcardAccount,
            )
          else if (_kcardAccount != null && _kcardAccount!.isNotEmpty)
            SelectableText(
              _kcardAccount!,
              style: TextStyle(color: AppColors.textStrong, fontSize: 16),
              textDirection: TextDirection.ltr,
            )
          else
            Text(
              t('wallet_account_not_set'),
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          const SizedBox(height: 10),
          if (!_loadingAccount && !_accountFailed && _kcardAccount != null)
            SelectableText(
              t('wallet_kcard_payment_instructions'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              textDirection: appLocale.direction,
            ),
        ],
      ),
    );
  }

  Widget _buildReceiptSection() {
    final hasReceipt = _receiptFile != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('wallet_receipt'),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 10),
          if (hasReceipt && _receiptBytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                _receiptBytes!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    Text(t('wallet_upload_receipt_failed')),
              ),
            ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _submitting || _picking ? null : _pickReceipt,
            icon: const Icon(Icons.upload_file, size: 18),
            label: Text(
              _picking
                  ? t('common_loading_dots')
                  : hasReceipt
                  ? t('wallet_upload_receipt')
                  : t('wallet_pick_receipt'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmittedSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppColors.shadow,
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 48),
          const SizedBox(height: 12),
          Text(
            t('wallet_submitted_success'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            t('wallet_topup_pending'),
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_receiptFile != null)
            FutureBuilder<Uint8List>(
              future: _receiptFile!.readAsBytes(),
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      snapshot.data!,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          FutureBuilder<bool>(
            future: currentUserIsAdmin(),
            builder: (context, snapshot) {
              final isAdmin = snapshot.data == true;
              if (!isAdmin) return const SizedBox.shrink();
              return FilledButton.icon(
                onPressed: _submitting ? null : _confirmAsAdmin,
                style: FilledButton.styleFrom(
                  backgroundColor: red,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.admin_panel_settings, size: 18),
                label: Text(_submitting ? '' : t('wallet_confirm_admin')),
              );
            },
          ),
        ],
      ),
    );
  }
}
