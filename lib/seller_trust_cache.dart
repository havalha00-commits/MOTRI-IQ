// ذاكرة مؤقتة داخل الجلسة للبيانات التي تُقرأ داخل البطاقات:
// المفضلة، سمعة البائع، وتوثيق البائع.
//
// قبل هذا الملف كان كل CarCard يرسل استعلامين خاصين به (favorites +
// seller_reviews) في initState، أي 40 طلباً إضافياً عند عرض 20 بطاقة،
// وكل تمرير يعيد بناء البطاقات فيجلب الطلبات من جديد. الآن تجلب الصفحات
// البيانات مرة واحدة لكل الدفعة عبر preload، وتقرأ البطاقات من الذاكرة.
//
// لا تغيير في قاعدة البيانات: نفس الاستعلامات، نفس الأعمدة، نفس الصلاحيات.
// عمر الذاكرة = عمر التطبيق فقط، وتُبطَل عند تبديل المستخدم.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:motri_iq/backend_api.dart';
import 'auth/backend_auth_session.dart';

class TrustCache extends ChangeNotifier {
  TrustCache(
    this.authSession, {
    required this.loadFavoriteRows,
    required this.loadSellerReviews,
    required this.loadSellerVerifications,
  }) {
    _auth = () {
      _scopeFavorites();
      scheduleMicrotask(() {
        if (!_disposed) unawaited(preloadFavorites());
      });
    };
    authSession.addListener(_auth);
  }
  late final VoidCallback _auth;
  bool _disposed = false, _notifyQueued = false;
  int _favoritesGeneration = 0;
  final _favoriteOverrides = <String, bool>{};
  final _favoriteReads = <String, Future<bool>>{};
  final _favoriteWrites = <String>{};
  void _notifyFavorites() {
    if (_notifyQueued || _disposed) return;
    _notifyQueued = true;
    scheduleMicrotask(() {
      _notifyQueued = false;
      if (!_disposed) notifyListeners();
    });
  }

  void _scopeFavorites() {
    final user = authSession.user?.id;
    if (_favUserId == user) return;
    _clearFavorites();
    _favUserId = user;
  }

  void _clearFavorites() {
    _favoritesGeneration++;
    _favoritesLoaded = false;
    _favoritesInFlight = null;
    _favoriteIds.clear();
    _favoriteOverrides.clear();
    _favoriteReads.clear();
    _favoriteWrites.clear();
    _notifyFavorites();
  }

  int? beginFavoriteChange(String id) {
    _scopeFavorites();
    if (_favUserId == null || !_favoriteWrites.add(id)) return null;
    _notifyFavorites();
    return _favoritesGeneration;
  }

  bool favoriteChangeCurrent(String id, int generation) =>
      generation == _favoritesGeneration &&
      _favUserId == authSession.user?.id &&
      _favoriteWrites.contains(id);
  bool favoriteBusy(String id) {
    _scopeFavorites();
    return _favoriteWrites.contains(id);
  }

  void endFavoriteChange(String id, int generation) {
    if (generation != _favoritesGeneration) return;
    _favoriteWrites.remove(id);
    _notifyFavorites();
  }

  @override
  void dispose() {
    _disposed = true;
    authSession.removeListener(_auth);
    super.dispose();
  }

  final BackendAuthSession authSession;
  final Future<List<Map<String, dynamic>>> Function(String userId)?
      loadFavoriteRows;
  final Future<List<Map<String, dynamic>>> Function(List<String> sellerIds)
      loadSellerReviews;
  final Future<List<Map<String, dynamic>>> Function(List<String> sellerIds)
      loadSellerVerifications;

  Future<List<Map<String, dynamic>>> _favoriteRows(String userId) async {
    final loader = loadFavoriteRows;
    if (loader == null) throw StateError('Favorite API is not configured');
    return loader(userId);
  }

  /// أقصى عدد معرّفات في طلب واحد (طول عنوان URL في PostgREST محدود).
  /// زيد إلى 100 لتقليل عدد الطلبات عند جلب سمعة/توثيق بائعين متعددين.
  static const int _chunk = 100;

  /// أقصى عدد بائعين في دفعة واحدة حتى لا يصير الطلب طويلاً جداً.
  /// زيد إلى 300 لتحسين الأداء عند تحميل صفحات كبيرة.
  static const int _maxBatch = 300;

  // ------------------------------------------------------------ المفضلة
  String? _favUserId;
  bool _favoritesLoaded = false;
  final Set<String> _favoriteIds = <String>{};
  Future<void>? _favoritesInFlight;

  /// Whether favorites were successfully loaded for the current account scope.
  /// Auth failures must not set this true and must not clear loaded IDs.
  bool get favoritesLoaded {
    _scopeFavorites();
    return _favoritesLoaded;
  }

  /// Snapshot of loaded favorite IDs (effective IDs only; overrides applied).
  Set<String> favoriteIdsSnapshot() {
    _scopeFavorites();
    if (!_favoritesLoaded) return <String>{};
    final out = Set<String>.from(_favoriteIds);
    for (final e in _favoriteOverrides.entries) {
      if (e.value) {
        out.add(e.key);
      } else {
        out.remove(e.key);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ السمعة
  final Map<String, Map<String, dynamic>> _reputation =
      <String, Map<String, dynamic>>{};
  final Set<String> _reputationFetched = <String>{};
  final Set<String> _reputationInFlight = <String>{};

  /// طلب بدأه متصل آخر وننتظر نتيجته. بدونها كانت بطاقة ثانية لنفس البائع
  /// تُقرأ أثناء جلب الأولى فترى "لا يوجد" وتعرض بلا شارة، لأن الجلب الأول
  /// لم يكتمل بعد.
  final Map<String, Future<void>> _reputationWait = <String, Future<void>>{};

  // ------------------------------------------------------------ التوثيق
  final Map<String, bool> _verified = <String, bool>{};
  final Set<String> _verifiedFetched = <String>{};
  final Set<String> _verifiedInFlight = <String>{};
  final Map<String, Future<void>> _verifiedWait = <String, Future<void>>{};

  // ------------------------------------------------------------ أدوات
  static String? _sellerIdOf(Object? row) {
    if (row is! Map) return null;
    final id = row['user_id']?.toString().trim() ?? '';
    if (id.isEmpty || id == 'null') return null;
    return id;
  }

  static List<List<String>> _batches(List<String> ids) {
    final List<List<String>> parts = <List<String>>[];
    for (var i = 0; i < ids.length; i += _chunk) {
      parts.add(
          ids.sublist(i, i + _chunk > ids.length ? ids.length : i + _chunk));
    }
    return parts;
  }

  // ------------------------------------------------------------ المفضلة
  /// مزامنة المفضلة مرة واحدة لكل مستخدم (استعلام واحد بدل واحد لكل بطاقة).
  Future<void> preloadFavorites() async {
    _scopeFavorites();
    final userId = _favUserId;
    if (userId == null || _favoritesLoaded) return;
    if (_favoritesInFlight != null) return _favoritesInFlight;
    final generation = _favoritesGeneration;
    final run = () async {
      try {
        final rows = await _favoriteRows(userId);
        if (generation != _favoritesGeneration ||
            authSession.user?.id != userId) {
          return;
        }
        _favoriteIds
          ..clear()
          ..addAll(rows
              .map((r) => r['car_id']?.toString() ?? '')
              .where((id) => id.isNotEmpty));
        for (final entry in _favoriteOverrides.entries) {
          if (entry.value) {
            _favoriteIds.add(entry.key);
          } else {
            _favoriteIds.remove(entry.key);
          }
        }
        _favoritesLoaded = true;
        _notifyFavorites();
      } on BackendApiException catch (e) {
        // Auth failure is not proof of "no favorites". Preserve prior IDs/loaded
        // state for the same account so cache-driven UI is not wiped.
        if (e.message == 'Backend authentication required') {
          if (generation == _favoritesGeneration &&
              authSession.user?.id == userId) {
            return;
          }
          return;
        }
        // Transient backend error: preserve known IDs (no empty wipe). Keep loaded
        // state if already loaded so UI is not treated as confirmed empty.
        if (generation == _favoritesGeneration) {
          if (!_favoritesLoaded) _favoritesLoaded = false;
        }
      } catch (_) {
        if (generation == _favoritesGeneration) {
          if (!_favoritesLoaded) _favoritesLoaded = false;
        }
      }
    }();
    _favoritesInFlight = run;
    await run;
    if (identical(_favoritesInFlight, run)) _favoritesInFlight = null;
  }

  bool isFavorite(String? id) {
    _scopeFavorites();
    return id != null && (_favoriteOverrides[id] ?? _favoriteIds.contains(id));
  }

  Future<bool> favoriteOf(String? id) async {
    _scopeFavorites();
    if (id == null || id.isEmpty || _favUserId == null) return false;
    final generation = _favoritesGeneration;
    if (_favoritesLoaded || _favoriteOverrides.containsKey(id)) {
      return isFavorite(id);
    }
    await preloadFavorites();
    if (generation != _favoritesGeneration) return isFavorite(id);
    if (_favoritesLoaded || _favoriteOverrides.containsKey(id)) {
      return isFavorite(id);
    }
    return _favoriteReads.putIfAbsent(
        id, () => _singleFavorite(id, generation));
  }

  Future<bool> _singleFavorite(String id, int generation) async {
    final userId = _favUserId;
    try {
      final rows = await _favoriteRows(userId!);
      if (generation != _favoritesGeneration ||
          userId != authSession.user?.id) {
        return false;
      }
      _favoriteOverrides.putIfAbsent(
        id,
        () => rows.any((row) => row['car_id']?.toString() == id),
      );
      _notifyFavorites();
      return isFavorite(id);
    } on BackendApiException catch (e) {
      if (e.message == 'Backend authentication required') return false;
      return false;
    } catch (_) {
      return false;
    } finally {
      if (generation == _favoritesGeneration) _favoriteReads.remove(id);
    }
  }

  void setFavorite(String? id, bool value) {
    _scopeFavorites();
    if (id == null || id.isEmpty || _favUserId == null) return;
    _favoriteOverrides[id] = value;
    if (value) {
      _favoriteIds.add(id);
    } else {
      _favoriteIds.remove(id);
    }
    _notifyFavorites();
  }

  // ------------------------------------------------------------ السمعة
  static String tierFor(double avg, int count) {
    if (avg >= 4.5 && count >= 10) return 'gold';
    if (avg >= 4.0 && count >= 5) return 'silver';
    if (avg >= 3.5 && count >= 1) return 'bronze';
    return 'none';
  }

  Map<String, dynamic>? reputationOf(String? sellerId) =>
      sellerId == null ? null : _reputation[sellerId];

  bool hasReputation(String? sellerId) =>
      sellerId != null && _reputationFetched.contains(sellerId);

  /// استعلام واحد لكل البائعين دفعة واحدة (بدل استعلام لكل بطاقة).
  Future<void> preloadReputations(Iterable<String?> sellerIds) async {
    final List<String> wanted = _unique(sellerIds);

    // (1) إن كان جلب لنفس البائع بدأه متصل آخر، ننتظره بدل إعطاء نتيجة فارغة.
    for (final id in wanted) {
      if (_reputationFetched.contains(id)) continue;
      final pending = _reputationWait[id];
      if (pending == null) continue;
      try {
        await pending;
      } catch (_) {}
    }

    final List<String> missing = _missing(
      wanted,
      _reputationFetched,
      _reputationInFlight,
    );
    if (missing.isEmpty) return;
    for (final id in missing) {
      _reputationInFlight.add(id);
    }

    late final Future<void> run;
    run = () async {
      try {
        for (final part in _batches(missing)) {
          try {
            final rows = await loadSellerReviews(part);
            _absorbReviews(rows);
          } catch (_) {
            // نُعيد تحميل هذا الجزء في المرة القادمة بدل تخزين قيمة وهمية.
            for (final id in part) {
              _reputationFetched.remove(id);
            }
          }
        }
      } finally {
        for (final id in missing) {
          _reputationInFlight.remove(id);
          _reputationFetched.add(id);
          _reputation.putIfAbsent(id, () => <String, dynamic>{});
          _reputationWait.remove(id);
        }
      }
    }();

    // تُسجَّل قبل أول await كي يلحق بها أي متصل يطلب نفس البائع بعدها.
    for (final id in missing) {
      _reputationWait[id] = run;
    }
    await run;
  }

  static List<String> _unique(Iterable<String?> ids) {
    final List<String> out = <String>[];
    for (final id in ids) {
      if (id == null || id.isEmpty) continue;
      if (out.contains(id)) continue;
      out.add(id);
    }
    return out;
  }

  static List<String> _missing(
    Iterable<String> ids,
    Set<String> fetched,
    Set<String> inFlight,
  ) {
    final List<String> out = <String>[];
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (fetched.contains(id) || inFlight.contains(id)) continue;
      if (out.contains(id)) continue;
      out.add(id);
      if (out.length >= _maxBatch) break;
    }
    return out;
  }

  void _absorbReviews(Object? rows) {
    final Map<String, int> counts = <String, int>{};
    final Map<String, int> sums = <String, int>{};
    for (final raw in (rows as List<dynamic>)) {
      final row = raw as Map<String, dynamic>;
      final id = row['seller_id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final rating = (row['rating'] as num?)?.toInt() ?? 0;
      counts[id] = (counts[id] ?? 0) + 1;
      sums[id] = (sums[id] ?? 0) + rating;
    }
    counts.forEach((id, count) {
      final avg = (sums[id] ?? 0) / count;
      _reputation[id] = <String, dynamic>{
        'badge_tier': tierFor(avg, count),
        'avg_rating': avg,
        'review_count': count,
      };
    });
  }

  /// ذاكرة أولاً، ثم استعلام واحد عند الحاجة (تفادي المفضلة في التفاصيل).
  Future<Map<String, dynamic>?> reputationOfFuture(String? sellerId) async {
    if (sellerId == null || sellerId.isEmpty) return null;
    if (_reputationFetched.contains(sellerId)) {
      final cached = _reputation[sellerId];
      return (cached == null || cached.isEmpty) ? null : cached;
    }
    await preloadReputations(<String>[sellerId]);
    final value = _reputation[sellerId];
    if (value == null || value.isEmpty) return null;
    return value;
  }

  // ------------------------------------------------------------ التوثيق
  bool isVerified(String? sellerId) =>
      sellerId != null && _verified[sellerId] == true;

  /// استعلام واحد لكل البائعين دفعة واحدة (بدل استعلام لكل بطاقة).
  Future<void> preloadVerifications(Iterable<String?> sellerIds) async {
    final List<String> wanted = _unique(sellerIds);

    for (final id in wanted) {
      if (_verifiedFetched.contains(id)) continue;
      final pending = _verifiedWait[id];
      if (pending == null) continue;
      try {
        await pending;
      } catch (_) {}
    }

    final List<String> missing =
        _missing(wanted, _verifiedFetched, _verifiedInFlight);
    if (missing.isEmpty) return;
    for (final id in missing) {
      _verifiedInFlight.add(id);
    }

    late final Future<void> run;
    run = () async {
      try {
        for (final part in _batches(missing)) {
          try {
            final rows = await loadSellerVerifications(part);
            for (final raw in (rows as List<dynamic>)) {
              final id = (raw as Map<String, dynamic>)['seller_id']?.toString();
              if (id != null && id.isNotEmpty) _verified[id] = true;
            }
            for (final id in part) {
              _verified.putIfAbsent(id, () => false);
            }
          } catch (_) {
            for (final id in part) {
              _verifiedFetched.remove(id);
            }
          }
        }
      } finally {
        for (final id in missing) {
          _verifiedInFlight.remove(id);
          _verifiedFetched.add(id);
          _verified.putIfAbsent(id, () => false);
          _verifiedWait.remove(id);
        }
      }
    }();

    for (final id in missing) {
      _verifiedWait[id] = run;
    }
    await run;
  }

  Future<bool> verifiedOf(String? sellerId) async {
    if (sellerId == null || sellerId.isEmpty) return false;
    if (_verifiedFetched.contains(sellerId)) {
      return _verified[sellerId] == true;
    }
    await preloadVerifications(<String>[sellerId]);
    return _verified[sellerId] == true;
  }

  // ------------------------------------------------------------ نقطة دخول واحدة
  /// تُستدعى بعد تحميل أي قائمة إعلانات: تجلب سمعة وتوثيق كل البائعين
  /// (استعلامان بدل 2×N) وتزامن المفضلة (استعلام واحد بدل N).
  Future<void> preloadForRows(
    Iterable<Map<String, dynamic>> rows, {
    bool withFavorites = true,
  }) async {
    final Set<String?> sellers = <String?>{};
    for (final row in rows) {
      sellers.add(_sellerIdOf(row));
    }
    await Future.wait(<Future<void>>[
      preloadReputations(sellers),
      preloadVerifications(sellers),
      if (withFavorites) preloadFavorites(),
    ]);
  }

  /// نسيان بائع واحد (بعد تقييم جديد أو تعديل).
  void invalidateSeller(String? sellerId) {
    if (sellerId == null || sellerId.isEmpty) return;
    _reputation.remove(sellerId);
    _reputationFetched.remove(sellerId);
    _verified.remove(sellerId);
    _verifiedFetched.remove(sellerId);
  }

  /// تُبطَل عند تبديل المستخدم حتى لا تتسرب بيانات بين حسابين.
  void reset() {
    _clearFavorites();
    _favUserId = authSession.user?.id;
    _reputation.clear();
    _reputationFetched.clear();
    _reputationWait.clear();
    _verified.clear();
    _verifiedFetched.clear();
    _verifiedWait.clear();
  }
}
