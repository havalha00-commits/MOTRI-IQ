import 'package:flutter/material.dart';

/// Result delivery waits until text inputs are removed from the overlay, so a
/// caller can safely release temporary controllers after awaiting this dialog.
Future<T?> showSettledDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) async {
  final route = DialogRoute<T>(context: context, builder: builder);
  final result = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  return result;
}
