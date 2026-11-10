import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/ui/account_feed_state.dart';
import 'package:motri_iq/ui/app_state_panel.dart';
import 'package:motri_iq/ui/content_direction.dart';
import 'package:motri_iq/ui/form_section.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/design/app_icons.dart';

class _WalletReviewResult {
  const _WalletReviewResult.ready(this.rows) : failed = false, denied = false;
  const _WalletReviewResult.failed()
    : rows = const [],
      failed = true,
      denied = false;
  const _WalletReviewResult.denied()
    : rows = const [],
      failed = false,
      denied = true;
  final List<Map<String, dynamic>> rows;
  final bool failed, denied;
}

class WalletAdminReviewPage extends StatefulWidget {
  const WalletAdminReviewPage({super.key});

  @override
  State<WalletAdminReviewPage> createState() => _WalletAdminReviewPageState();
}

class _WalletAdminReviewPageState extends State<WalletAdminReviewPage>
    with AccountFeedState<WalletAdminReviewPage> {
  late Future<_WalletReviewResult> _pendingTxns;
  final Set<String> _processingIds = {};
  String? _openingReceiptId;

  @override
  void reloadAccountFeed() {
    _processingIds.clear();
    _openingReceiptId = null;
    _pendingTxns = _loadPending();
  }

  @override
  void initState() {
    super.initState();
    _pendingTxns = _loadPending();
  }

  Future<void> _openReceipt(String id) async {
    if (_openingReceiptId != null || _processingIds.isNotEmpty) return;
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!accountMatches(actor, epoch)) return;
    setState(() {
      _openingReceiptId = id;
    });
    try {
      final res = await backendApi.get('wallet/topups/$id/receipt/signed');
      final data = res is Map ? res['data'] : null;
      final url = data is Map ? data['url']?.toString() : null;
      if (url == null || url.isEmpty) {
        throw const FormatException('Invalid receipt URL');
      }
      if (!mounted || !accountMatches(actor, epoch)) return;
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('Receipt could not be opened');
    } catch (_) {
      if (!mounted || !accountMatches(actor, epoch)) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(t('wallet_receipt_open_failed'))));
    } finally {
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _openingReceiptId = null;
        });
      }
    }
  }

  Future<_WalletReviewResult> _loadPending() async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!backendAuthSession.isAuthenticated || actor == null) {
      return const _WalletReviewResult.denied();
    }
    try {
      final res = await backendApi.get('wallet/admin/pending');
      if (!accountMatches(actor, epoch)) return const _WalletReviewResult.denied();
      final data = res is Map ? res['data'] : null;
      final rows = data is List
          ? data.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : <Map<String, dynamic>>[];
      return _WalletReviewResult.ready(rows);
    } on BackendApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        return const _WalletReviewResult.denied();
      }
      return accountMatches(actor, epoch)
          ? const _WalletReviewResult.failed()
          : const _WalletReviewResult.denied();
    } catch (_) {
      return accountMatches(actor, epoch)
          ? const _WalletReviewResult.failed()
          : const _WalletReviewResult.denied();
    }
  }

  String _requester(Map<String, dynamic> tx) {
    final name = tx['requester_name']?.toString().trim() ?? '';
    return name.isNotEmpty
        ? name
        : tx['user_id']?.toString() ?? t('common_user');
  }

  Future<void> _decide(Map<String, dynamic> tx, String status) async {
    final actor = backendAuthSession.user?.id;
    final epoch = accountEpoch;
    if (!accountMatches(actor, epoch)) return;
    final id = tx['id']?.toString();
    if (id == null ||
        id.isEmpty ||
        _processingIds.isNotEmpty ||
        _openingReceiptId != null) {
      return;
    }
    setState(() {
      _processingIds.add(id);
    });
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          scrollable: true,
          title: Text(
            t(status == 'confirmed' ? 'wallet_approve' : 'wallet_reject'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(t('ui_wallet_decision_prompt')),
              const SizedBox(height: 16),
              Text(t('wallet_amount'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(formatIqd((tx['amount'] as num?)?.toInt() ?? 0),
                  key: const ValueKey('wallet_decision_amount'),
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(t('ui_wallet_requester'), style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(_requester(tx),
                  key: const ValueKey('wallet_decision_requester'),
                  textDirection: contentTextDirection(context, _requester(tx)),
                  style: Theme.of(context).textTheme.titleMedium),
              if (_requester(tx) != tx['user_id']?.toString()) ...[
                const SizedBox(height: 4),
                Text(tx['user_id']?.toString() ?? '', textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(t('common_cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                t(status == 'confirmed' ? 'wallet_approve' : 'wallet_reject'),
              ),
            ),
          ],
        ),
      );
      if (!mounted || !accountMatches(actor, epoch) || approved != true) return;
      final result = await backendApi.post(
        'wallet/decide',
        body: {'id': id, 'status': status},
      );
      if (!mounted || !accountMatches(actor, epoch)) return;
      final ok =
          result is Map && result['ok'] == true && result['status'] == status;
      final reason = result is Map ? result['reason'] : null;
      final message = ok
          ? t(
              status == 'confirmed'
                  ? 'wallet_admin_approve_success'
                  : 'wallet_admin_reject_success',
            )
          : reason == 'already_decided'
          ? t('ui_wallet_already_decided')
          : t('payment_update_failed');
      if (ok ||
          reason == 'already_decided' ||
          reason == 'not_admin' ||
          reason == 'not_authenticated') {
        final pending = _loadPending();
        setState(() {
          _pendingTxns = pending;
        });
        await pending;
      }
      if (mounted && accountMatches(actor, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      if (mounted && accountMatches(actor, epoch)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t('payment_update_failed'))));
      }
    } finally {
      if (mounted && accountMatches(actor, epoch)) {
        setState(() {
          _processingIds.remove(id);
        });
      }
    }
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    try {
      final dt = DateTime.parse(iso);
      return '${dt.year}/${dt.month}/${dt.day}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('admin_wallet_title'))),
        body: FutureBuilder<_WalletReviewResult>(
          future: _pendingTxns,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AppLoadingView(label: t('ui_loading_title'));
            }
            if (snapshot.hasError || snapshot.data?.failed == true) {
              return _loadError(
                () => setState(() {
                  _pendingTxns = _loadPending();
                }),
              );
            }
            if (snapshot.data?.denied == true) {
              return AppStateView(
                title: t('admin_only_notice'),
                icon: AppIcons.locked,
              );
            }
            final items = snapshot.data?.rows ?? const [];
            if (items.isEmpty) {
              return AppStateView(
                title: t('wallet_no_pending'),
                icon: AppIcons.receipt,
              );
            }
            return RefreshIndicator(
              onRefresh: () async {
                if (_processingIds.isNotEmpty || _openingReceiptId != null) {
                  return;
                }
                final future = _loadPending();
                setState(() {
                  _pendingTxns = future;
                });
                try {
                  await future;
                } catch (_) {
                  /* FutureBuilder presents retry. */
                }
              },
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 30),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final tx = items[i];
                  final txId = tx['id'].toString();
                  final processing = _processingIds.contains(txId);
                  return Container(
                    padding: const EdgeInsets.all(14),
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
                          _requester(tx),
                          textDirection: contentTextDirection(context, _requester(tx)),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (_requester(tx) != tx['user_id']?.toString())
                          SelectableText(
                            tx['user_id']?.toString() ?? '',
                            textDirection: TextDirection.ltr,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 8),
                        Text(
                          formatIqd((tx['amount'] as num?)?.toInt() ?? 0),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onPrimaryContainer,
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t('wallet_status_pending'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${t('wallet_submitted_at')}: ${_formatDate(tx['created_at'] as String?)}',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          t('wallet_payment_method'),
                          style: TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          tx['payment_method'] == null ||
                                  tx['payment_method'] == 'kcard'
                              ? t('wallet_kcard')
                              : tx['payment_method'].toString(),
                          style: TextStyle(
                            color: AppColors.textStrong,
                            fontSize: 13,
                          ),
                        ),
                        if ((tx['receipt_image_url'] as String?)?.isNotEmpty ==
                            true)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: OutlinedButton.icon(
                              onPressed:
                                  _processingIds.isNotEmpty ||
                                      _openingReceiptId != null
                                  ? null
                                  : () => _openReceipt(txId),
                              icon: _openingReceiptId == txId
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(AppIcons.receipt),
                              label: Text(t('wallet_receipt')),
                            ),
                          ),
                        const SizedBox(height: 10),
                        ResponsiveFormPair(
                          first: OutlinedButton.icon(
                            onPressed:
                                _processingIds.isNotEmpty ||
                                    _openingReceiptId != null
                                ? null
                                : () => _decide(tx, 'rejected'),
                            icon: const Icon(Icons.close_rounded),
                            label: Text(t('wallet_reject')),
                          ),
                          second: FilledButton.icon(
                            onPressed:
                                _processingIds.isNotEmpty ||
                                    _openingReceiptId != null
                                ? null
                                : () => _decide(tx, 'confirmed'),
                            icon: processing
                                ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                : const Icon(Icons.check_rounded),
                            label: Text(t('wallet_approve')),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

Widget _loadError(VoidCallback onRetry) => AppStateView(
  title: t('ui_load_error_title'), message: t('ui_load_error_body'),
  icon: AppIcons.cloudOff, isError: true,
  actionLabel: t('ui_retry'), onAction: onRetry,
);
