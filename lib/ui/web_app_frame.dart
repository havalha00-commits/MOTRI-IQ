import 'package:flutter/material.dart';

/// Keeps the mobile client preview readable in a desktop browser.
class WebAppFrame extends StatelessWidget {
  const WebAppFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: LayoutBuilder(
            builder: (context, constraints) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                size: Size(constraints.maxWidth, constraints.maxHeight),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
