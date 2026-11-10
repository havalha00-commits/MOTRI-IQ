import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('floating labels remain readable in $brightness', () {
      final theme = buildAppTheme(brightness);
      final background = theme.inputDecorationTheme.fillColor!;
      final style = theme.inputDecorationTheme.floatingLabelStyle!
          as WidgetStateTextStyle;
      for (final states in [
        <WidgetState>{},
        {WidgetState.focused},
        {WidgetState.focused, WidgetState.error}
      ]) {
        final foreground = style.resolve(states).color!;
        final a = foreground.computeLuminance(),
            b = background.computeLuminance();
        final contrast = ((a > b ? a : b) + .05) / ((a < b ? a : b) + .05);
        expect(contrast, greaterThanOrEqualTo(4.5),
            reason: 'Floating labels are small text: $states');
      }
    });
  }
}
