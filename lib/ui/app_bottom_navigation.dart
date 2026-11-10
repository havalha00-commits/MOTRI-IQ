import 'package:flutter/material.dart';
import '../design/app_icons.dart';
import '../l10n/app_delegates.dart';
import '../l10n/app_locale.dart';

/// Six stable destinations with native selection, focus and screen-reader cues.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation(
      {super.key, required this.selectedIndex, required this.onSelected});
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    context.dependOnAppStrings();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .65)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? .16 : .04),
              blurRadius: 20,
              offset: const Offset(0, -4))
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Align(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: LayoutBuilder(
                  builder: (context, constraints) => NavigationBar(
                        key: const ValueKey('app_bottom_navigation'),
                        selectedIndex: selectedIndex,
                        onDestinationSelected: onSelected,
                        height: 76,
                        animationDuration:
                            MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                        backgroundColor: scheme.surface,
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        indicatorColor: scheme.primary,
                        indicatorShape: const StadiumBorder(),
                        labelBehavior:
                            NavigationDestinationLabelBehavior.alwaysShow,
                        labelPadding: const EdgeInsets.only(top: 5),
                        labelTextStyle:
                            WidgetStateProperty.resolveWith((states) {
                          final base = theme.navigationBarTheme.labelTextStyle
                                  ?.resolve(states) ??
                              theme.textTheme.labelMedium!;
                          return base.copyWith(
                              fontSize: constraints.maxWidth >= 420 ? 12 : 11,
                              height: 1.25,
                              color: states.contains(WidgetState.selected)
                                  ? (theme.brightness == Brightness.dark
                                      ? scheme.onSurface
                                      : scheme.primary)
                                  : base.color);
                        }),
                        destinations: [
                          for (final destination in const [
                            (AppIcons.home, 'nav_home'),
                            (AppIcons.cars, 'nav_cars'),
                            (AppIcons.market, 'nav_market'),
                            (AppIcons.search, 'nav_search'),
                            (AppIcons.add, 'nav_add'),
                            (AppIcons.account, 'nav_account'),
                          ])
                            NavigationDestination(
                              key: ValueKey(destination.$2),
                              label: t(destination.$2),
                              tooltip: t(destination.$2),
                              icon: _DestinationIcon(
                                  icon: destination.$1,
                                  add: destination.$2 == 'nav_add',
                                  selected: false),
                              selectedIcon: _DestinationIcon(
                                  icon: destination.$1,
                                  add: destination.$2 == 'nav_add',
                                  selected: true),
                            ),
                        ],
                      )),
            )),
      ),
    );
  }
}

class _DestinationIcon extends StatelessWidget {
  const _DestinationIcon(
      {required this.icon, required this.add, required this.selected});
  final IconData icon;
  final bool add, selected;
  @override
  Widget build(BuildContext context) => Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: add
            ? BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(11))
            : null,
        child: Icon(icon,
            size: 24,
            fill: selected ? 1 : 0,
            weight: selected ? 500 : 400,
            opticalSize: 24,
            color: add || selected
                ? Theme.of(context).colorScheme.onPrimary
                : null),
      );
}
