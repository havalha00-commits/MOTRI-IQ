import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'plate_detector.dart';

/// دالة تركيبية تُحمّل شعار MOTRI IQ كـ Uint8List.
/// يتم تحميله مرة واحدة وتخزينه مؤقتياً.
Uint8List? _cachedLogoBytes;

Future<Uint8List> loadMotriLogoBytes() async {
  if (_cachedLogoBytes != null) return _cachedLogoBytes!;
  final data = await rootBundle.load('assets/logo/motri_iq_logo.png');
  _cachedLogoBytes = data.buffer.asUint8List();
  return _cachedLogoBytes!;
}

/// Processing image cache with LRU eviction to prevent memory bloat.
/// Max 50 processed images (~50-100MB depending on image size).
class ProcessedImageCache {
  static const int _maxSize = 50;
  final Map<String, Uint8List> _cache = {};
  final List<String> _accessOrder = [];

  Uint8List? get(String key) {
    if (!_cache.containsKey(key)) return null;
    _accessOrder.remove(key);
    _accessOrder.add(key);
    return _cache[key];
  }

  void set(String key, Uint8List value) {
    if (_cache.containsKey(key)) {
      _accessOrder.remove(key);
    } else if (_cache.length >= _maxSize) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
    _cache[key] = value;
    _accessOrder.add(key);
  }

  bool containsKey(String key) => _cache.containsKey(key);
}

final ProcessedImageCache processedImageCache = ProcessedImageCache();

Future<Uint8List> processCarImageWithWatermark(
  Uint8List originalBytes, {
  List<PlateRegion>? plateRegions,
}) async {
  final cacheKey = _cacheKey(originalBytes, plateRegions);
  final cached = processedImageCache.get(cacheKey);
  if (cached != null) return cached;

  final img.Image? original = img.decodeImage(originalBytes);
  if (original == null) return originalBytes;

  final int w = original.width;
  final int h = original.height;

  // اكتشاف اللوحة إذا لم يتم توفير مناطق - نمرر الصورة المفكوكة لتجنب فك التشفير المزدوج
  final List<PlateRegion> regions =
      plateRegions ?? detectLicensePlates(originalBytes, decodedImage: original);
  if (regions.isEmpty) {
    // لا توجد لوحة — أرجع الصورة الأصلية دون تعديل
    processedImageCache.set(cacheKey, originalBytes);
    return originalBytes;
  }

  // استخدم أولى لوحة تم اكتشافها
  final region = regions.first;

  // تحميل شعار MOTRI IQ
  final logoBytes = await loadMotriLogoBytes();
  final img.Image? logo = img.decodeImage(logoBytes);
  if (logo == null) {
    processedImageCache.set(cacheKey, originalBytes);
    return originalBytes;
  }

  // حساب موقع الشعار لتغطية اللوحة تماماً
  final int plateX = (region.x * w).round();
  final int plateY = (region.y * h).round();
  final int plateW = (region.width * w).round();
  final int plateH = (region.height * h).round();

  // اجعل الشعار أكبر قليلاً من اللوحة للتغطية الكاملة
  final int logoW = (plateW * 1.2).round();
  final int logoH = (plateH * 1.2).round();

  // وضع الشعار في منتصف اللوحة
  final int dstX = (plateX + (plateW - logoW) ~/ 2).clamp(0, w - 1);
  final int dstY = (plateY + (plateH - logoH) ~/ 2).clamp(0, h - 1);

  // دمج الشعار مع الصورة الأصلية باستخدام compositeImage
  img.compositeImage(
    original,
    logo,
    dstX: dstX,
    dstY: dstY,
    dstW: logoW,
    dstH: logoH,
  );

  final Uint8List processed = img.encodeJpg(original, quality: 90);

  processedImageCache.set(cacheKey, processed);
  return processed;
}

String _cacheKey(Uint8List bytes, List<PlateRegion>? regions) {
  if (regions == null || regions.isEmpty) {
    return '${bytes.length}_${bytes.hashCode}';
  }
  final buffer = StringBuffer();
  for (final r in regions) {
    buffer.write('${r.x},${r.y},${r.width},${r.height};');
  }
  return '${bytes.length}_${bytes.hashCode}_${buffer.toString()}';
}
