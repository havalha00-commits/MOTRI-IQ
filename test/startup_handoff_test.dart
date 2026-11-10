import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/l10n/app_locale.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'fixture',
      authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      httpClient: MockClient((request) async {
        expectSync(request.method, 'GET',
            reason: 'Startup review permits only isolated reads');
        return http.Response(jsonEncode([]), 200,
            request: request,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
  });
  for (final locale in AppLocale.values) {
    for (final dark in [false, true]) {
      testWidgets('Startup opens Home immediately ${locale.code} dark=$dark',
          (tester) async {
        if (!const bool.fromEnvironment('NATIVE_VIEWPORT')) {
          tester.view.physicalSize = const Size(320, 480);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
        }
        appLocaleNotifier.value = locale;
        AppColors.isDark = dark;
        darkModeNotifier.value = dark ? ThemeMode.dark : ThemeMode.light;
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData.fromView(tester.view).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(1.8)),
          child: const MotriIqApp(),
        ));
        // Resolve localization delegates without advancing a startup delay.
        await tester.pump();
        // No artificial timer or intermediate route before the usable shell.
        expect(find.byType(HomePage), findsOneWidget);
        final media = MediaQuery.of(tester.element(find.byType(HomePage)));
        expect(media.textScaler.scale(10), 18);
        expect(media.disableAnimations, isTrue);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(find.text(t('nav_home')), findsWidgets);
        expect(Directionality.of(tester.element(find.byType(NavigationBar))),
            locale.direction);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 30));
        }
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('UI_STARTUP_HOLD') &&
            ((locale == AppLocale.ar && !dark) ||
                (locale == AppLocale.ku && dark))) {
          debugPrint('STARTUP_${locale.code.toUpperCase()}');
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 15)));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
      });
    }
  }
}
