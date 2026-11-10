import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// منطقة لوحة سيارة تم اكتشافها.
/// القيم نسبية (0.0 إلى 1.0) بالنسبة لعرض وارتفاع الصورة.
class PlateRegion {
  final double x;
  final double y;
  final double width;
  final double height;

  PlateRegion(this.x, this.y, this.width, this.height);

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        'w': width,
        'h': height,
      };

  factory PlateRegion.fromJson(Map<String, dynamic> json) => PlateRegion(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['w'] as num).toDouble(),
        (json['h'] as num).toDouble(),
      );
}

/// يكتشف لوحة السيارة في الصورة باستخدام خوارزمية خفيفة.
///
/// الخوارزمية تعتمد على:
/// 1. تحويل إلى رمادي
/// 2. تطبيق عتبة بسيطة للعثور على المناطق البيضاء/الصفراء (ألوان اللوحات)
/// 3. البحث عن مستطيلات في النصف السفلي من الصورة
/// 4. تصفية المرشحات بحسب نسبة الأبعاد وحجمها
///
/// يرجع أفضل مرشح واحد أو null إذا لم يتم العثور على لوحة.
/// يمكن تمرير `decodedImage` لتجنب فك تشفير الصورة مرتين.
List<PlateRegion> detectLicensePlates(Uint8List bytes, {img.Image? decodedImage}) {
  final img.Image? original = decodedImage ?? img.decodeImage(bytes);
  if (original == null) return [];

  final int w = original.width;
  final int h = original.height;
  if (w < 100 || h < 100) return [];

  // تحويل إلى رمادي
  final gray = img.grayscale(original);

  // البحث في النصف السفلي 60% من الصورة
  final searchStartY = (h * 0.3).round();
  final searchEndY = h;

  // عتبة للبيضاء/الصفراء (القيم العالية في الرمادي)
  // اللوحات العراقية بيضاء أو صفراء مع نص أسود
  final whiteThreshold = 200;

  // البحث عن مستطيلات متراكمة
  // نستخدم منهجية بسيطة: نبحث عن صفوف متتالية من البكسلات المتفوقة على العتبة
  // ثم ندمجها إلى مستطيلات محتملة للوحة

  final List<_Candidate> candidates = [];
  bool inRegion = false;
  int regionStartY = 0;
  int regionStartX = 0;
  int regionEndX = 0;

  for (int y = searchStartY; y < searchEndY; y++) {
    bool rowHasWhite = false;
    int rowWhiteStart = -1;
    int rowWhiteEnd = -1;

    for (int x = 0; x < w; x++) {
      final pixel = gray.getPixel(x, y);
      final num grayValue = pixel.r;
      if (grayValue > whiteThreshold) {
        if (!rowHasWhite) {
          rowWhiteStart = x;
          rowWhiteEnd = x;
          rowHasWhite = true;
        } else {
          rowWhiteEnd = x;
        }
      }
    }

    if (rowHasWhite) {
      final runWidth = rowWhiteEnd - rowWhiteStart + 1;
      if (runWidth >= 30) {
        if (!inRegion) {
          inRegion = true;
          regionStartY = y;
          regionStartX = rowWhiteStart;
          regionEndX = rowWhiteEnd;
        } else {
          // تمديد المنطقة
          regionStartX = (regionStartX + rowWhiteStart) ~/ 2;
          regionEndX = (regionEndX + rowWhiteEnd) ~/ 2;
        }
      } else {
        // الصف غير الطويل بما يكفي - إنهاء المنطقة الحالية
        if (inRegion) {
          final height = y - regionStartY;
          final candidateWidth = regionEndX - regionStartX;
          if (_isPlateLike(candidateWidth, height)) {
            candidates.add(_Candidate(regionStartX, regionStartY,
                candidateWidth, height, runWidth));
          }
          inRegion = false;
        }
      }
    } else {
      // لا توجد بكسلات بيضاء - إنهاء المنطقة الحالية
      if (inRegion) {
        final height = y - regionStartY;
        final candidateWidth = regionEndX - regionStartX;
        if (_isPlateLike(candidateWidth, height)) {
          candidates.add(_Candidate(regionStartX, regionStartY,
              candidateWidth, height, regionEndX - regionStartX));
        }
        inRegion = false;
      }
    }
  }

  // إنهاء آخر منطقة إذا لزم الأمر
  if (inRegion) {
    final height = searchEndY - regionStartY;
    final candidateWidth = regionEndX - regionStartX;
    if (_isPlateLike(candidateWidth, height)) {
      candidates.add(_Candidate(regionStartX, regionStartY,
          candidateWidth, height, regionEndX - regionStartX));
    }
  }

  if (candidates.isEmpty) return [];

  // تصفية ودمج المرشحات المتداخلة
  candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

  final List<PlateRegion> result = [];
  for (final c in candidates) {
    bool overlaps = false;
    for (final r in result) {
      final double px = c.x / w;
      final double py = c.y / h;
      final double pw = c.width / w;
      final double ph = c.height / h;
      // التحقق من التداخل
      final double cx = px + pw / 2;
      final double cy = py + ph / 2;
      if ((cx - r.x - r.width / 2).abs() < (r.width + pw) / 2 &&
          (cy - r.y - r.height / 2).abs() < (r.height + ph) / 2) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) {
      result.add(PlateRegion(
        c.x / w,
        c.y / h,
        c.width / w,
        c.height / h,
      ));
    }
  }

  return result;
}

bool _isPlateLike(int width, int height) {
  if (width < 30 || height < 10) return false;
  final double aspect = width / height;
  // اللوحات العراقية نسبة عرض/ارتفاع تتراوح بين 2 و 5
  return aspect >= 1.5 && aspect <= 6.0;
}

class _Candidate {
  final int x, y, width, height, confidence;
  _Candidate(this.x, this.y, this.width, this.height, this.confidence);
}
