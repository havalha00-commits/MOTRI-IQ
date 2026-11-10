import 'package:flutter/material.dart';

/// Shared, content-sized empty/error presentation for cards and full screens.
class AppStatePanel extends StatelessWidget {
  const AppStatePanel(
      {super.key,
      required this.title,
      required this.icon,
      this.message,
      this.actionLabel,
      this.onAction,
      this.isError = false});
  final String title;
  final String? message, actionLabel;
  final IconData icon;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: isError,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ExcludeSemantics(
              child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isError ? scheme.errorContainer : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon,
                size: 28,
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onPrimaryContainer),
          )),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
          if (message != null && message!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message!,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5)),
          ],
          if (onAction != null && actionLabel != null) ...[
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel!, textAlign: TextAlign.center),
                )),
          ],
        ]),
      ),
    );
  }
}

/// Scroll on short displays or with a keyboard/large text, rather than clipping.
class AppStateView extends StatelessWidget {
  const AppStateView(
      {super.key,
      required this.title,
      required this.icon,
      this.message,
      this.actionLabel,
      this.onAction,
      this.isError = false});
  final String title;
  final String? message, actionLabel;
  final IconData icon;
  final VoidCallback? onAction;
  final bool isError;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final panel = Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: AppStatePanel(
              title: title,
              icon: icon,
              message: message,
              actionLabel: actionLabel,
              onAction: onAction,
              isError: isError),
        ));
        if (!constraints.hasBoundedHeight) {
          return Padding(padding: const EdgeInsets.all(20), child: panel);
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight:
                    (constraints.maxHeight - 40).clamp(0, double.infinity)),
            child: panel,
          ),
        );
      });
}

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, semanticsLabel: label)),
          const SizedBox(height: 16),
          Text(label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ));
}
