import 'package:flutter/material.dart';

/// Quiet grouping for the business editor's long form.
class BusinessFormSection extends StatelessWidget {
  const BusinessFormSection(
      {super.key,
      required this.title,
      required this.icon,
      required this.children});
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
            header: true,
            child: Row(children: [
              Icon(icon,
                  size: 20, color: scheme.onSurface.withValues(alpha: .65)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurface))),
            ])),
        const SizedBox(height: 20),
        ...children,
      ]),
    );
  }
}
