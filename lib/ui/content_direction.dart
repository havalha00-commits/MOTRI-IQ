import 'package:flutter/material.dart';

/// Follows the draft's first strong character without replacing its controller
/// or editing value, so selections and IME composing ranges remain intact.
class ContentDirectionBuilder extends StatelessWidget {
  const ContentDirectionBuilder(
      {super.key, required this.controller, required this.builder});
  final TextEditingController controller;
  final Widget Function(BuildContext context, TextDirection direction) builder;

  @override
  Widget build(BuildContext context) =>
      ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) =>
              builder(context, contentTextDirection(context, value.text)));
}

TextDirection contentTextDirection(BuildContext context, String value,
    {TextDirection? fallback}) {
  final first = RegExp(
          r'[A-Za-z\u00C0-\u024F\u0620-\u064A\u066E-\u06D3\u06FA-\u06FF\u0750-\u077F\u08A0-\u08FF]')
      .firstMatch(value)
      ?.group(0);
  if (first == null) return fallback ?? Directionality.of(context);
  return RegExp(r'[A-Za-z\u00C0-\u024F]').hasMatch(first)
      ? TextDirection.ltr
      : TextDirection.rtl;
}
