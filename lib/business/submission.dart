import 'dart:typed_data';
import '../backend_api.dart';
import '../submission_id.dart';

class BusinessDraftPhoto {
  BusinessDraftPhoto(
      {required this.id,
      required this.name,
      required Uint8List bytes,
      required this.folder})
      : bytes = Uint8List.fromList(bytes);
  final String id, name, folder;
  final Uint8List bytes;
}

enum BusinessSubmissionStage { photos, listing, order }

/// A route-owned, resumable request. Once a listing insert has been attempted,
/// its payload stays fixed so a retry can acknowledge the same request safely.
class BusinessSubmission {
  BusinessSubmission({
    required this.api,
    required this.currentUserId,
    this.timeout = const Duration(seconds: 30),
  });
  final BackendApi api;
  final String? Function() currentUserId;
  final Duration timeout;
  final adId = newSubmissionId();
  String? ownerId;
  final _uploads = <String, String>{};
  Map<String, dynamic>? _ad;
  bool _running = false;
  bool get locked => _ad != null;

  Future<String> submit(
      {required Map<String, dynamic> fields,
      required BusinessDraftPhoto logo,
      required List<BusinessDraftPhoto> photos,
      required String packageId,
      required double price,
      required int durationDays,
      required bool Function() active,
      required void Function(BusinessSubmissionStage) progress}) async {
    if (_running) throw StateError('Submission already running');
    final owner = currentUserId();
    if (owner == null || ownerId != null && ownerId != owner) {
      throw StateError('Submission account changed');
    }
    ownerId = owner;
    // Freeze caller-owned data before the first asynchronous operation.
    final snapshot = Map<String, dynamic>.of(fields);
    final selection = List<BusinessDraftPhoto>.of(photos);
    void check() {
      if (!active() || currentUserId() != owner) {
        throw StateError('Submission no longer active');
      }
    }

    Future<String> upload(BusinessDraftPhoto photo) async {
      check();
      final cached = _uploads[photo.id];
      if (cached != null) return cached;
      final ext = photo.name.split('.').last.toLowerCase();
      final safe = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
      final path = '$owner/${photo.folder}/$adId/${photo.id}.$safe';
      final response = await api
          .putBytes(
            'uploads/object',
            query: {'bucket': 'business_ads', 'path': path},
            body: photo.bytes,
            contentType: safe == 'jpg' || safe == 'jpeg'
                ? 'image/jpeg'
                : 'image/$safe',
          )
          .timeout(timeout);
      check();
      if (response is! Map ||
          response['data'] is! Map ||
          response['data']['public_url'] is! String) {
        throw StateError('Image upload acknowledgement missing');
      }
      return _uploads[photo.id] = response['data']['public_url'] as String;
    }

    _running = true;
    try {
      check();
      if (!locked) {
        if (!price.isFinite ||
            price < 0 ||
            durationDays < 1 ||
            packageId.isEmpty) {
          throw StateError('Invalid package');
        }
        progress(BusinessSubmissionStage.photos);
        final logoUrl = await upload(logo);
        final images = <String>[];
        for (final photo in selection) {
          images.add(await upload(photo));
        }
        check();
        _ad = {
          ...snapshot,
          'logo_url': logoUrl,
          'image_urls': images,
          'package_id': packageId,
        };
      }
      progress(BusinessSubmissionStage.listing);
      final currentOwner = currentUserId();
      if (currentOwner == null || currentOwner != owner) {
        throw StateError('Submission account changed');
      }
      final submissionFields = Map<String, dynamic>.from(_ad!)
        ..remove('logo_url')
        ..remove('image_urls')
        ..remove('package_id');
      final response = await api
          .post(
            'business-ads/submissions',
            body: {
              'ad_id': adId,
              'package_id': packageId,
              'fields': submissionFields,
              'logo_url': _ad!['logo_url'],
              'image_urls': _ad!['image_urls'],
            },
          )
          .timeout(timeout);
      check();
      final ownerAfter = currentUserId();
      if (ownerAfter == null || ownerAfter != owner) {
        throw StateError('Submission account changed');
      }
      if (response is! Map ||
          response['data'] is! Map ||
          response['data']['ad_id']?.toString() != adId) {
        throw StateError('Business submission acknowledgement missing');
      }
      progress(BusinessSubmissionStage.order);
      return adId;
    } finally {
      _running = false;
    }
  }
}
