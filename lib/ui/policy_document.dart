import 'package:flutter/material.dart';

class PolicyDocument extends StatelessWidget {
  const PolicyDocument(
      {super.key,
      required this.title,
      required this.sections,
      required this.updatedLabel});
  final String title, updatedLabel;
  final List<(String, String)> sections;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
            top: false,
            child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: SelectionArea(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              for (final section in sections)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                            color: theme.colorScheme.surface,
                                            border: Border.all(
                                                color: theme.colorScheme
                                                    .outlineVariant),
                                            borderRadius:
                                                BorderRadius.circular(18)),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Text(section.$1,
                                                  style: theme
                                                      .textTheme.titleMedium),
                                              const SizedBox(height: 10),
                                              Text(section.$2,
                                                  style: theme
                                                      .textTheme.bodyLarge
                                                      ?.copyWith(height: 1.7)),
                                            ]))),
                              const SizedBox(height: 8),
                              Text(updatedLabel,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall),
                            ])))))));
  }
}
