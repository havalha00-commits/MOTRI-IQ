import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/main.dart';
import 'package:motri_iq/release_channel.dart';
import 'package:motri_iq/home_banner_ad.dart';
import 'package:motri_iq/l10n/app_locale.dart';
import 'package:motri_iq/ui/account_deletion_page.dart';
import 'package:motri_iq/wallet/wallet_top_up_page.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('Play restriction is Android-only', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(restrictPaidFeatures, playStoreBuild);
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(restrictPaidFeatures, false);
  });

  test('Play business advertising feed does not access the backend', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(await loadActiveBusinessAds(), isEmpty);
  }, skip: !playStoreBuild);

  testWidgets('First release exposes no banner or ad privacy controls', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(const MaterialApp(home: Column(children: [
      HomeBannerAd(), AdPrivacyOptionsButton(),
    ])));
    expect(find.byType(TextButton), findsNothing);
    expect(find.byType(SizedBox), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final page in <Widget>[
    const CreateBusinessAdPage(),
    const WalletTopUpPage(),
  ]) {
    testWidgets('Play blocks ${page.runtimeType} before backend initialization',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(MaterialApp(home: page));
      expect(find.text(t('play_paid_unavailable_body')), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    }, skip: !playStoreBuild);
  }

  testWidgets('Deletion screen opens only the public portal without account data',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(MaterialApp(
      home: AccountDeletionPage(onOpen: (_, url) async => opened = url),
    ));
    await tester.tap(find.text(t('account_delete_open')));
    expect(opened?.scheme, 'https');
    expect(opened?.toString(), accountDeletionUrl);
    expect(opened?.query, isEmpty);
    expect(find.textContaining('@'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
