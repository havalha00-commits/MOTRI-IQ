import 'package:flutter/material.dart';

/// A bounded position indicator remains legible even for a long vehicle feed.
class CarouselPosition extends StatelessWidget {
  const CarouselPosition(
      {super.key,
      required this.count,
      required this.active,
      required this.color,
      required this.inactiveColor});
  final int count, active;
  final Color color, inactiveColor;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox.shrink();
    final current = active.clamp(0, count - 1);
    final visible = count.clamp(0, 5);
    final start = (current - 2).clamp(0, count - visible);
    return Semantics(
      value: '${current + 1} / $count',
      child: ExcludeSemantics(
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = start; i < start + visible; i++)
            AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == current ? 18 : 5,
              height: 5,
              decoration: BoxDecoration(
                color: i == current ? color : inactiveColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          if (count > 5) ...[
            const SizedBox(width: 10),
            Text('${current + 1} / $count',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }
}
