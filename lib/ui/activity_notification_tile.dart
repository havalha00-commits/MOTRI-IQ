import 'content_direction.dart';
import '../design/app_icons.dart';
import 'package:flutter/material.dart';

/// Wrapping activity content with an explicit unread label and directional action.
class ActivityNotificationTile extends StatelessWidget {
  const ActivityNotificationTile(
      {super.key,
      required this.title,
      required this.body,
      required this.icon,
      required this.unreadLabel,
      required this.unread,
      this.detail,
      this.bodyMaxLines,
      this.busy = false,
      this.onTap});
  final String title, body, unreadLabel;
  final IconData icon;
  final bool unread, busy;
  final String? detail;
  final int? bodyMaxLines;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
              color:
                  unread ? scheme.onPrimaryContainer : scheme.outlineVariant)),
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child:
                      Icon(icon, size: 22, color: scheme.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        textDirection: contentTextDirection(context, title),
                        style: Theme.of(context).textTheme.titleSmall),
                    if (body.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(body,
                          textDirection: contentTextDirection(context, body),
                          maxLines: bodyMaxLines,
                          overflow: bodyMaxLines == null
                              ? null
                              : TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium)
                    ],
                    if (detail != null && detail!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(detail!,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: scheme.onPrimaryContainer)),
                    ],
                    if (unread) ...[
                      const SizedBox(height: 10),
                      Text(unreadLabel,
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(color: scheme.onPrimaryContainer))
                    ],
                  ])),
              const SizedBox(width: 8),
              if (busy)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(AppIcons.disclosure, color: scheme.onSurfaceVariant),
            ])),
      ),
    );
  }
}
