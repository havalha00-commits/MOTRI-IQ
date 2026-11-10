import 'package:flutter/material.dart';
import '../l10n/app_locale.dart';

class LanguagePickerSheet extends StatelessWidget {
  const LanguagePickerSheet({super.key, required this.selected});
  final AppLocale selected;
  @override
  Widget build(BuildContext context) => SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: SingleChildScrollView(
          child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                    padding: const EdgeInsetsDirectional.only(start: 12),
                    child: Row(children: [
                      Expanded(
                          child: Text(t('account_language'),
                              style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(
                          tooltip: MaterialLocalizations.of(context)
                              .closeButtonTooltip,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded)),
                    ])),
                RadioGroup<AppLocale>(
                    groupValue: selected,
                    onChanged: (value) {
                      Navigator.pop(context, value ?? selected);
                    },
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final option in AppLocale.values)
                        RadioListTile<AppLocale>(
                          value: option,
                          toggleable: true,
                          fillColor: WidgetStateProperty.resolveWith((states) {
                            final theme = Theme.of(context);
                            if (states.contains(WidgetState.selected)) {
                              return theme.brightness == Brightness.dark
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.primary;
                            }
                            return theme.colorScheme.onSurfaceVariant;
                          }),
                          title: Text(option.label,
                              textDirection: option.direction),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12),
                        ),
                    ])),
              ])),
        ),
      ));
}
