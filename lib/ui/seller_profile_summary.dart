import 'package:flutter/material.dart';

/// Description and reputation share the tile's bounded text column, rather than
/// competing for a single line beside the avatar and disclosure arrow.
class SellerProfileSummary extends StatelessWidget {
  const SellerProfileSummary({
    super.key,
    required this.description,
    required this.tierLabel,
    required this.rating,
    required this.reviewCount,
    required this.badgeColor,
    required this.textColor,
  });

  final String description, tierLabel;
  final double rating;
  final int reviewCount;
  final Color badgeColor, textColor;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(description, style: TextStyle(color: textColor)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.star_rounded, color: badgeColor, size: 16),
                  ),
                  TextSpan(text: ' $tierLabel'),
                ]),
                style: TextStyle(color: badgeColor, fontSize: 12),
              ),
              Text('★ ${rating.toStringAsFixed(1)} ($reviewCount)',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: badgeColor, fontSize: 12)),
            ],
          ),
        ],
      );
}
