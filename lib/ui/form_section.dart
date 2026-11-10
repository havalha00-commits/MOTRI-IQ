import 'package:flutter/material.dart';
import '../search/smart_query.dart';

class FormSectionHeading extends StatelessWidget {
  const FormSectionHeading(
      {super.key, required this.title, required this.icon, this.description});
  final String title;
  final IconData icon;
  final String? description;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: Semantics(
            header: true,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon,
                      size: 20,
                      color: Theme.of(context).colorScheme.onPrimaryContainer)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    if (description != null) ...[
                      const SizedBox(height: 4),
                      Text(description!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)),
                    ],
                  ])),
            ])),
      );
}

class ResponsiveFormPair extends StatelessWidget {
  const ResponsiveFormPair(
      {super.key, required this.first, required this.second});
  final Widget first, second;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(14) > 17) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: 12), second]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: first),
          const SizedBox(width: 12),
          Expanded(child: second)
        ]);
      });
}

TextDirection formInputDirection(
        TextInputType type, TextDirection localeDirection) =>
    {
      TextInputType.number.index,
      TextInputType.phone.index,
      TextInputType.emailAddress.index,
      TextInputType.url.index,
      TextInputType.visiblePassword.index
    }.contains(type.index)
        ? TextDirection.ltr
        : localeDirection;

String normalizeFormNumber(String value) => normalizeForSearch(value)
    .replaceAll(RegExp(r'[\s,،٬]'), '')
    .replaceAll('٫', '.');
int? parseFormInteger(String value) => int.tryParse(normalizeFormNumber(value));
double? parseFormDecimal(String value) {
  final parsed = double.tryParse(normalizeFormNumber(value));
  return parsed != null && parsed.isFinite ? parsed : null;
}
