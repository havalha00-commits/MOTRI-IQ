import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';
import '../l10n/app_delegates.dart';
import '../release_channel.dart';

class AccountDeletionPage extends StatelessWidget {
  const AccountDeletionPage({super.key, required this.onOpen});
  final Future<void> Function(BuildContext context, Uri url) onOpen;

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    return Directionality(
      textDirection: appLocale.direction,
      child: Scaffold(
        appBar: AppBar(title: Text(t('account_delete_title'))),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t('account_delete_body'),
                    style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onOpen(context, Uri.parse(accountDeletionUrl)),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(t('account_delete_open')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
