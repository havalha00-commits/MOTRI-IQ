import 'package:flutter/material.dart';
import '../design/app_icons.dart';

/// A photo-led summary. Full fields remain available in the detail route.
class CompactListingCard extends StatelessWidget {
  const CompactListingCard(
      {super.key,
      required this.photo,
      required this.title,
      required this.onTap,
      this.titleDirection,
      this.homeSectionStyle = false,
      this.primaryPrice = '',
      this.secondaryPrice = '',
      this.previousPrice = '',
      this.metadata = '',
      this.location = '',
      this.photoActions = const []});
  final Widget photo;
  final String title,
      primaryPrice,
      secondaryPrice,
      previousPrice,
      metadata,
      location;
  final TextDirection? titleDirection;
  final bool homeSectionStyle;
  final VoidCallback onTap;
  final List<Widget> photoActions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side:
              BorderSide(color: scheme.outlineVariant.withValues(alpha: .55))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
          onTap: onTap,
          child: LayoutBuilder(builder: (context, size) {
            if (homeSectionStyle) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1.65,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [photo, ...photoActions],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            title,
                            textDirection: titleDirection,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: metadata
                                  .split(' • ')
                                  .where((value) => value.trim().isNotEmpty)
                                  .map(
                                    (value) => Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: scheme.outlineVariant,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        value,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 9,
                                          height: 1.3,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                          const Spacer(),
                          Row(
                            textDirection: TextDirection.ltr,
                            children: [
                              if (primaryPrice.isNotEmpty)
                                Flexible(
                                  flex: location.isNotEmpty ? 3 : 1,
                                  fit: FlexFit.tight,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (previousPrice.isNotEmpty)
                                        Text(
                                          previousPrice,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 9,
                                            decoration:
                                                TextDecoration.lineThrough,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      Text(
                                        primaryPrice,
                                        textDirection: TextDirection.ltr,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: scheme.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (location.isNotEmpty) ...[
                                Flexible(
                                  flex: primaryPrice.isNotEmpty ? 2 : 1,
                                  fit: FlexFit.tight,
                                  child: Directionality(
                                    textDirection: TextDirection.rtl,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          AppIcons.location,
                                          size: 12,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 2),
                                        Flexible(
                                          child: Text(
                                            location,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 10,
                                              height: 1.3,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            final secondary = secondaryPrice.isNotEmpty &&
                size.maxHeight >=
                    size.maxWidth * .6 + scaler.scale(13) * 8 + 20;
            return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                      fit: FlexFit.loose,
                      child: AspectRatio(
                          aspectRatio: 4 / 3,
                          child: Stack(
                              fit: StackFit.expand,
                              children: [photo, ...photoActions]))),
                  Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(title,
                              textDirection: titleDirection,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  fontWeight: FontWeight.w700)),
                          if (primaryPrice.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            if (secondary && previousPrice.isNotEmpty)
                              Text(previousPrice,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 10,
                                      height: 1.35,
                                      decoration: TextDecoration.lineThrough,
                                      color: scheme.onSurfaceVariant)),
                            Text(primaryPrice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    fontWeight: FontWeight.w800)),
                          ],
                          if (secondary)
                            Text(secondaryPrice,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 10,
                                    height: 1.35,
                                    color: scheme.onSurfaceVariant)),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(metadata,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: scheme.onSurfaceVariant)),
                          ],
                          if (location.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(AppIcons.location,
                                  size: 14, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Expanded(
                                  child: Text(location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 11,
                                          height: 1.35,
                                          color: scheme.onSurfaceVariant))),
                            ]),
                          ],
                        ],
                      )),
                ]);
          })),
    );
  }
}
