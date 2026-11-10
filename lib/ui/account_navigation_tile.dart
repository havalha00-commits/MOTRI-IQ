import '../design/app_icons.dart';
import 'package:flutter/material.dart';

class AccountNavigationTile extends StatelessWidget {
  const AccountNavigationTile(
      {super.key,
      required this.icon,
      required this.title,
      this.onTap,
      this.danger = false});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool danger;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
              side: BorderSide(color: scheme.outlineVariant)),
          child: ListTile(
            contentPadding: const EdgeInsetsDirectional.fromSTEB(14, 6, 12, 6),
            onTap: onTap,
            leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: danger
                        ? scheme.errorContainer
                        : scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(icon,
                    size: 22,
                    color: danger
                        ? scheme.onErrorContainer
                        : scheme.onPrimaryContainer)),
            title: Text(title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: danger ? scheme.error : scheme.onSurface)),
            trailing: Icon(AppIcons.disclosure, color: scheme.onSurfaceVariant),
          ),
        ));
  }
}
