import 'package:flutter/material.dart';
import '../design/app_icons.dart';
import 'content_direction.dart';

class SellerProfileHeader extends StatelessWidget {
  const SellerProfileHeader(
      {super.key,
      required this.name,
      required this.location,
      required this.description,
      required this.rating,
      required this.reviewCountLabel,
      required this.listingCountLabel,
      required this.actions,
      this.verifiedLabel,
      this.tierLabel,
      this.tierColor});
  final String name, location, description, reviewCountLabel, listingCountLabel;
  final double rating;
  final String? verifiedLabel, tierLabel;
  final Color? tierColor;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(
            child: CircleAvatar(
                radius: 30,
                backgroundColor: scheme.primaryContainer,
                child: Icon(AppIcons.market,
                    color: scheme.onPrimaryContainer, size: 30))),
        const SizedBox(height: 16),
        Semantics(
            header: true,
            child: Text(name,
                textDirection: contentTextDirection(context, name),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800))),
        if (verifiedLabel != null || tierLabel != null) ...[
          const SizedBox(height: 10),
          Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                if (verifiedLabel != null)
                  _badge(context, Icons.verified_rounded, verifiedLabel!,
                      scheme.onPrimaryContainer),
                if (tierLabel != null)
                  _badge(context, Icons.workspace_premium_rounded, tierLabel!,
                      tierColor ?? scheme.onSurface),
              ]),
        ],
        if (location.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(location,
              textDirection: contentTextDirection(context, location),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant))
        ],
        if (description.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(description,
              textDirection: contentTextDirection(context, description),
              textAlign: TextAlign.center)
        ],
        const SizedBox(height: 16),
        Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              _badge(context, Icons.star_rounded, rating.toStringAsFixed(1),
                  scheme.onSurface),
              Text(reviewCountLabel, style: theme.textTheme.bodyMedium),
              Text(listingCountLabel, style: theme.textTheme.bodyMedium),
            ]),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 20),
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            actions[i],
          ],
        ],
      ]),
    );
  }

  Widget _badge(
          BuildContext context, IconData icon, String label, Color color) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 5),
          Flexible(
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600)))
        ],
      );
}
