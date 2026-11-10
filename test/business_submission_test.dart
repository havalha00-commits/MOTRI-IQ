import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:motri_iq/backend_api.dart';
import 'package:motri_iq/business/submission.dart';
import 'support/business_submission_fixture.dart';

void main() {
  final f = BusinessFixture();
  setUpAll(f.initialize);
  setUp(() {
    f.reset();
  });
  BusinessDraftPhoto photo(String id) => BusinessDraftPhoto(
      id: id,
      name: 'photo.png',
      bytes: Uint8List.fromList([1, 2, 3]),
      folder: id == 'logo' ? 'logos' : 'images');
  Future<String> send(BusinessSubmission draft,
          {Map<String, dynamic>? fields,
          List<BusinessDraftPhoto>? photos,
          bool Function()? active}) =>
      draft.submit(
          fields: fields ??
              {
                'business_name': 'MOTRI Service',
                'category': 'Parts',
                'phone': '07701234567'
              },
          logo: photo('logo'),
          photos: photos ?? [photo('first'), photo('second')],
          packageId: businessPackage,
          price: 25,
          durationDays: 30,
          active: active ?? () => true,
          progress: (_) {});
  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(condition(), isTrue);
  }

  test('business submission requires matching ad acknowledgement', () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
    expect(await send(draft), draft.adId);
    expect(f.writes('business_ads').length, 1);
    expect(f.writes('business_ad_orders').length, 0); // free-flow: no orders table write
    final ad = f.ads[draft.adId]!;
    expect(ad['status'], 'pending');
    expect(
        DateTime.parse(ad['end_at'])
            .difference(DateTime.parse(ad['start_at']))
            .inDays,
        30);
  });
  test(
      'business partial upload keeps completed files and reuses incomplete path',
      () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
    f.failUploadAt = 2;
    await expectLater(send(draft), throwsA(isA<BackendApiException>()));
    expect(draft.locked, isFalse);
    expect(f.requests, isEmpty);
    final path = f.uploads.last.url.queryParameters['path'];
    f.failUploadAt = 0;
    await send(draft, fields: {'business_name': 'Edited before insert'});
    expect(f.uploads.length, 4);
    expect(f.uploads[2].url.queryParameters['path'], path);
    expect(f.ads[draft.adId]!['business_name'], 'Edited before insert');
  });
  for (final table in ['business_ads']) {
    for (final ack in ['empty', 'wrong']) {
      test(
          'business $table $ack acknowledgement resumes the existing committed row',
          () async {
        final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
        if (ack == 'empty') {
          f.emptyAck = table;
        } else {
          f.wrongAck = table;
        }
        await expectLater(send(draft), throwsA(anyOf(isA<StateError>(), isA<BackendApiException>())));
        expect(draft.locked, isTrue);
        f.emptyAck = f.wrongAck = null;
        await send(draft,
            fields: {'business_name': 'Must not replace submitted details'});
        expect(f.writes(table).length, 2);
        expect(f.uploads.length, 3);
        expect(f.ads[draft.adId]!['business_name'], 'MOTRI Service');
        expect(f.requests, hasLength(2));
        expect(jsonDecode(f.requests.first.body)['ad_id'], draft.adId);
        expect(jsonDecode(f.requests.last.body)['ad_id'], draft.adId);
      });
    }
    test(
        'business $table rejected write retries same id without duplicating the other row',
        () async {
      final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
      f.failTable = table;
      await expectLater(send(draft), throwsA(anything));
      f.failTable = null;
      await send(draft);
      expect(f.writes(table).length, 2);
      expect(jsonDecode(f.writes(table).first.body)['ad_id'],
          jsonDecode(f.writes(table).last.body)['ad_id']);
      expect(f.ads.length, 1);
      expect(f.orders.length, 0);
      expect(f.uploads.length, 3);
    });
  }
  test('business snapshot cannot change while an upload is pending', () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id),
        fields = <String, dynamic>{'business_name': 'Original'};
    final photos = [photo('first'), photo('second')];
    f.uploadGate = Completer<void>();
    final pending = send(draft, fields: fields, photos: photos);
    await until(() => f.uploads.isNotEmpty);
    fields['business_name'] = 'Changed';
    photos.clear();
    f.uploadGate!.complete();
    await pending;
    expect(f.ads[draft.adId]!['business_name'], 'Original');
    expect(f.ads[draft.adId]!['image_urls'], hasLength(2));
  });
  test('business concurrent submission is rejected while original continues',
      () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
    f.uploadGate = Completer<void>();
    final pending = send(draft);
    await until(() => f.uploads.isNotEmpty);
    await expectLater(send(draft), throwsA(anyOf(isA<StateError>(), isA<BackendApiException>())));
    f.uploadGate!.complete();
    await pending;
    expect(f.ads.length, 1);
    expect(f.orders.length, 0);
  });
  test('business disposal after atomic submission prevents navigation',
      () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
    var active = true;
    f.adGate = Completer<void>();
    final pending = send(draft, active: () => active);
    await until(() => f.writes('business_ads').isNotEmpty);
    active = false;
    f.adGate!.complete();
    await expectLater(pending, throwsStateError);
    expect(f.orders, hasLength(0));
  });
  test('business session loss during upload prevents all row writes', () async {
    final draft = BusinessSubmission(api: f.api, currentUserId: () => f.client.auth.currentUser?.id);
    f.uploadGate = Completer<void>();
    final pending = send(draft);
    await until(() => f.uploads.isNotEmpty);
    await f.client.auth.signOut();
    f.uploadGate!.complete();
    await expectLater(pending, throwsStateError);
    expect(f.requests, isEmpty);
    await f.signIn();
  });
  test(
      'business timeout releases pending guard and keeps stable upload identity',
      () async {
    final draft =
        BusinessSubmission(
            api: f.api,
            currentUserId: () => f.client.auth.currentUser?.id,
            timeout: const Duration(milliseconds: 25));
    f.uploadGate = Completer<void>();
    await expectLater(send(draft), throwsA(isA<TimeoutException>()));
    final path = f.uploads.single.url.queryParameters['path'];
    f.uploadGate!.complete();
    f.uploadGate = null;
    await send(draft);
    expect(f.uploads[1].url.queryParameters['path'], path);
    expect(f.ads.length, 1);
  });
}
