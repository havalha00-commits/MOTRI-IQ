import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/l10n/app_delegates.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/main.dart';

void main() {
  for (final grid in [false, true]) {
    testWidgets(
        'car listing photo fills its frame in ${grid ? 'grid' : 'list'} layout',
        (tester) async {
      appLocaleNotifier.value = AppLocale.en;
      await tester.pumpWidget(MaterialApp(
        locale: appLocale.locale,
        supportedLocales: const [Locale('ar'), Locale('ku'), Locale('en')],
        localizationsDelegates: appLocalizationsDelegates,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 420,
            child: CarCard(
              car: const {'brand': 'Toyota', 'model': 'Corolla'},
              square: grid,
              homeSectionStyle: grid,
            ),
          ),
        ),
      ));
      await tester.pump();

      expect(tester.widget<CarPhoto>(find.byType(CarPhoto)).fit, BoxFit.cover);
      expect(tester.takeException(), isNull);
    });
  }
}
