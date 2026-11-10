import 'package:flutter/material.dart';
import '../backend_api.dart';

import '../l10n/app_delegates.dart';
import '../l10n/app_locale.dart';
import '../main.dart' show backendAuthSession;

Future<bool> ensureUgcPolicyAccepted(
  BuildContext context,
  Object? legacyClient,
  BackendApi api,
) async {
  final userId = backendAuthSession.user?.id;
  if (userId == null) return false;

  final status = await api.get('ugc/acceptance');
  if (!context.mounted || backendAuthSession.user?.id != userId) return false;
  if (status is! Map ||
      status['data'] is! Map ||
      status['data']['accepted'] is! bool) {
    throw StateError('Unexpected UGC policy acceptance response');
  }
  final accepted = status['data']['accepted'] as bool;
  if (accepted) return true;

  var checked = false;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        context.dependOnAppStrings();
        return Directionality(
          textDirection: appLocale.direction,
          child: AlertDialog(
            title: Text(t('ugc_policy_consent_title')),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    child: Text(t('ugc_policy_consent_body')),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: checked,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(t('ugc_policy_consent_checkbox')),
                    onChanged: (value) =>
                        setDialogState(() => checked = value ?? false),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(t('common_cancel')),
              ),
              FilledButton(
                onPressed:
                    checked ? () => Navigator.pop(dialogContext, true) : null,
                child: Text(t('ugc_policy_consent_accept')),
              ),
            ],
          ),
        );
      },
    ),
  );
  if (confirmed != true || backendAuthSession.user?.id != userId) {
    return false;
  }

  final result = await api.post(
    'ugc/acceptance',
    body: const {'policy_version': '2026-11-05'},
  );
  if (backendAuthSession.user?.id != userId ||
      result is! Map ||
      result['data'] is! Map ||
      result['data']['accepted'] != true) {
    throw StateError('UGC policy acceptance was not confirmed');
  }
  return true;
}
