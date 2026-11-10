import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/l10n/app_strings.dart';
import 'package:motri_iq/ui/seller_profile_summary.dart';

void main() {
  for (final locale in AppLocale.values) {
    for (final width in [320.0, 375.0, 430.0]) {
      for (final scale in [1.0, 1.5]) {
        testWidgets('${locale.code} seller tile at $width and text scale $scale',
            (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(scale)),
              child: Directionality(
                textDirection: locale.direction,
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ListTile(
                      titleAlignment: ListTileTitleAlignment.center,
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: const Text('MOTRI IQ', maxLines: 1),
                      subtitle: SellerProfileSummary(
                        description: AppStrings.t('misc_profile_view_desc', locale.code),
                        tierLabel: AppStrings.t('tier_bronze', locale.code),
                        rating: 5,
                        reviewCount: 12345,
                        badgeColor: Colors.orange,
                        textColor: Colors.black,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await tester.pump();
          expect(tester.takeException(), isNull);
          final description = find.text(AppStrings.t('misc_profile_view_desc', locale.code));
          final rating = find.text('★ 5.0 (12345)');
          expect(tester.getRect(rating).top, greaterThanOrEqualTo(tester.getRect(description).bottom));
          expect(tester.getRect(find.byType(ListTile)).contains(tester.getCenter(rating)), isTrue);
        });
      }
    }
  }
}
