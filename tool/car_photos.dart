// أداة سطر أوامر لتوحيد صور السيارات في التطبيق.
//
// الهدف: كل سيارة في قاعدة البيانات لها صورة بنفس الزاوية ونسبة الإطار
// والإضاءة، بدل خلط صور ويكيميديا المختلفة الخلفية والإضاءة.
//
// الاستخدام:
//   dart run tool/car_photos.dart pick     # يبحث في ويكيميديا ويختار صورة لكل سيارة
//   dart run tool/car_photos.dart build    # ينزّل ويوحّد الإضاءة ويبني لوحة معاينة
//   dart run tool/car_photos.dart apply    # يرفع الصور ويحدّث قاعدة البيانات
//
// الملفات:
//   car_photos/overrides.json  اختياري: تثبيت صورة معيّنة لموديل
//   car_photos/picked.json     ناتج pick: السيارات + الصور المختارة
//   car_photos/out/*.jpg       ناتج build: الصور بعد التوحيد (نفس ما يُرفع)
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

const String supabaseUrl = 'https://frfqpxviebzkyvppuzdb.supabase.co';
const String supabasePublishableKey =
    'sb_publishable_SjsZuIwSgA9G5Pqa1HZxDg_ABLQw959';

const String commonsApi = 'https://commons.wikimedia.org/w/api.php';
const String userAgent =
    'MOTRI-IQ car photo tool/1.0 (https://example.invalid; local demo tooling)';

const String carsBucket = 'cars';
const String storageFolder = 'studio';

// نفس النسبة المستخدمة في التطبيق (carPhotoAspect) حتى لا تُقصّ السيارة
// من أطرافها في أي شاشة.
const double outAspect = 4 / 3;
const int outWidth = 1600;
const int outHeight = 1200;
const int jpgQuality = 90;

const String dir = 'car_photos';
const String outDir = 'car_photos/out';

Future<void> main(List<String> args) async {
  final String command = args.isEmpty ? 'pick' : args.first;
  switch (command) {
    case 'pick':
      await cmdPick(args.skip(1).toList());
      break;
    case 'pin':
      await cmdPin();
      break;
    case 'build':
      await cmdBuild(args.skip(1).toList());
      break;
    case 'apply':
      await cmdApply(args.skip(1).toList());
      break;
    case 'stats':
      await cmdStats();
      break;
    default:
      stderr.writeln(
          'usage: dart run tool/car_photos.dart pick|pin|build|stats|apply');
      exitCode = 2;
  }
}

// ---------------------------------------------------------------------------
// stats: فحص كمّي لكل الصور بعد التوحيد + رصد الشاذ منها
// ---------------------------------------------------------------------------

Future<void> cmdStats() async {
  final files = Directory(outDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jpg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  var wrongSize = 0;
  var flagged = 0;
  final means = <double>[];
  final stds = <double>[];
  for (final file in files) {
    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) {
      stdout.writeln('${file.path}: فشل فك الترميز');
      flagged++;
      continue;
    }
    double sum = 0;
    double sum2 = 0;
    double sat = 0;
    var count = 0;
    for (final pixel in image) {
      final double luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
      sum += luma;
      sum2 += luma * luma;
      final double mx = [pixel.r, pixel.g, pixel.b]
          .map((v) => v.toDouble())
          .reduce((a, b) => a > b ? a : b);
      final double mn = [pixel.r, pixel.g, pixel.b]
          .map((v) => v.toDouble())
          .reduce((a, b) => a < b ? a : b);
      sat += mx <= 0 ? 0 : (mx - mn) / mx;
      count++;
    }
    final double mean = sum / count;
    final double std = math.sqrt(math.max(0, sum2 / count - mean * mean));
    means.add(mean);
    stds.add(std);
    final bool sizeOk = image.width == outWidth && image.height == outHeight;
    if (!sizeOk) wrongSize++;
    final bool outlier =
        mean < 105 || mean > 150 || std < 32 || std > 95 || !sizeOk;
    if (outlier) flagged++;
    stdout.writeln('${file.uri.pathSegments.last.padRight(34)} '
        '${image.width}x${image.height} '
        'إضاءة ${mean.toStringAsFixed(0).padLeft(3)} '
        'تباين ${std.toStringAsFixed(0).padLeft(3)} '
        'إشباع ${(sat / count * 100).toStringAsFixed(0).padLeft(3)}% '
        '${outlier ? '<-- راجع' : ''}');
  }
  if (means.isNotEmpty) {
    final double meanOfMeans = means.reduce((a, b) => a + b) / means.length;
    final double meanOfStds = stds.reduce((a, b) => a + b) / stds.length;
    stdout.writeln('--- ملخص (${means.length} صورة) ---');
    stdout.writeln('متوسط متوسط الإضاءة: ${meanOfMeans.toStringAsFixed(1)}');
    stdout.writeln('متوسط التباين: ${meanOfStds.toStringAsFixed(1)}');
    stdout.writeln('بمقاس خاطئ: $wrongSize   شاذة: $flagged');
  }
}

// ---------------------------------------------------------------------------
// pick: اختيار صورة لكل سيارة من ويكيميديا كومنز
// ---------------------------------------------------------------------------

Future<void> cmdPick(List<String> args) async {
  final int only = intArg(args, '--only') ?? -1;
  final bool restart = args.contains('--restart');
  final rows = await fetchCars();
  stdout.writeln('سيارات في القاعدة: ${rows.length}');

  final chosen = <String, List<String>>{};
  final pickedFile = File('$dir/picked.json');
  if (!restart && pickedFile.existsSync()) {
    final previous =
        jsonDecode(pickedFile.readAsStringSync()) as Map<String, dynamic>;
    (previous['chosen'] as Map<String, dynamic>).forEach((key, value) {
      chosen[key] = (value as List<dynamic>).cast<String>();
    });
    stdout.writeln('متابعة من نتيجة سابقة: ${chosen.length} سيارة');
  }

  final overrides = readOverrides();
  for (int i = 0; i < rows.length; i++) {
    if (only >= 0 && i != only) continue;
    final row = rows[i];
    final String key = rowKey(row);
    if (chosen.containsKey(key)) continue;
    final List<String>? pinned = overrides[key];
    if (pinned != null && pinned.isNotEmpty) {
      chosen[key] = pinned;
      stdout.writeln('[$i] ${_label(row)} <- مثبّت: ${pinned.first}');
      continue;
    }

    var candidates = await searchCandidates(row);
    if (candidates.isEmpty) {
      // محاولة ثانية باستعلام واحد أوسع بعد مهلة قصيرة.
      await Future<void>.delayed(const Duration(seconds: 2));
      candidates = await searchCandidates(row, wide: true);
    }
    if (candidates.isEmpty) {
      stdout.writeln('[$i] ${_label(row)} <- لا يوجد مرشّح');
      await Future<void>.delayed(const Duration(milliseconds: 250));
      continue;
    }
    final best = candidates.first;
    chosen[key] = [best.title];
    stdout.writeln('[$i] ${_label(row)} -> ${best.title} '
        '(${best.width}x${best.height} score=${best.score.round()})');
  }

  pickedFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'rows': rows,
    'chosen': chosen,
  }));
  stdout.writeln('حُفظ في $pickedFile (${chosen.length} سيارة)');
}

Future<List<Map<String, dynamic>>> fetchCars() async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/cars'
      '?select=id,user_id,brand,model,year,image_url'
      '&order=brand.asc,model.asc');
  final res = await http.get(uri, headers: {
    'apikey': supabasePublishableKey,
    'Authorization': 'Bearer $supabasePublishableKey',
  });
  if (res.statusCode != 200) {
    throw StateError('تعذّرت قراءة جدول السيارات: HTTP ${res.statusCode}');
  }
  final list = jsonDecode(res.body) as List<dynamic>;
  return [
    for (final item in list)
      {
        'id': item['id'],
        'user_id': item['user_id'],
        'brand': item['brand'],
        'model': item['model'],
        'year': item['year'],
      }
  ];
}

class Candidate {
  Candidate(this.title, this.url, this.thumb, this.width, this.height,
      this.mime, this.score);
  final String title;
  final String url;
  final String thumb;
  final int width;
  final int height;
  final String mime;
  final double score;
}

/// يطلب من ويكيميديا مع انتظار بين الطلبات وإعادة محاولة عند الازدحام
/// (429/503). لا بد من User-Agent محدد، ومنestrator طلبات قليلة.
DateTime _lastRequest = DateTime.fromMillisecondsSinceEpoch(0);

Future<http.Response?> commonsGet(Uri uri, {int attempts = 6}) async {
  for (var attempt = 0; attempt < attempts; attempt++) {
    final sinceLast = DateTime.now().difference(_lastRequest);
    if (sinceLast.inMilliseconds < 600) {
      await Future<void>.delayed(
          Duration(milliseconds: 600 - sinceLast.inMilliseconds));
    }
    _lastRequest = DateTime.now();
    try {
      final res = await http.get(uri, headers: {'User-Agent': userAgent});
      if (res.statusCode == 429 || res.statusCode == 503) {
        await Future<void>.delayed(Duration(seconds: 2 + attempt * 2));
        continue;
      }
      return res;
    } catch (e) {
      await Future<void>.delayed(Duration(milliseconds: 900 * (attempt + 1)));
    }
  }
  return null;
}

Future<List<Candidate>> searchCandidates(Map<String, dynamic> row,
    {bool wide = false}) async {
  final String brand = '${row['brand']}';
  final String model = '${row['model']}';
  final String year = '${row['year']}';
  final List<String> queries = wide
      ? ['$brand $model']
      : [
          '$brand $model $year',
          '$brand $model',
          '$brand $model front',
        ];

  final Map<String, Candidate> byTitle = <String, Candidate>{};
  for (final query in queries) {
    final uri = Uri.parse(commonsApi).replace(queryParameters: {
      'action': 'query',
      'format': 'json',
      'generator': 'search',
      'gsrsearch': 'filetype:bitmap $query',
      'gsrnamespace': '6',
      'gsrlimit': '30',
      'prop': 'imageinfo',
      'iiprop': 'url|size|mime',
      'iiurlwidth': '2000',
    });
    final res = await commonsGet(uri);
    if (res == null || res.statusCode != 200) {
      stdout.writeln('  بحث "${_label(row)}" فشل (${res?.statusCode})');
      continue;
    }
    final pages = (jsonDecode(res.body) as Map<String, dynamic>)['query'];
    if (pages == null) continue;
    for (final page in (pages as Map<String, dynamic>)['pages'].values
        as Iterable<dynamic>) {
      final map = page as Map<String, dynamic>;
      final info = (map['imageinfo'] as List<dynamic>?)?.firstOrNull;
      if (info == null) continue;
      final imageInfo = info as Map<String, dynamic>;
      final title = '${map['title']}';
      if (byTitle.containsKey(title)) continue;
      final width = (imageInfo['width'] as num?)?.toInt() ?? 0;
      final height = (imageInfo['height'] as num?)?.toInt() ?? 0;
      final mime = '${imageInfo['mime']}';
      final score =
          scoreCandidate(title, width, height, mime, brand, model, year);
      if (score == null) continue;
      byTitle[title] = Candidate(
        title,
        '${imageInfo['url']}',
        '${imageInfo['thumburl'] ?? imageInfo['url']}',
        width,
        height,
        mime,
        score,
      );
    }
  }

  final list = byTitle.values.toList()
    ..sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : b.width.compareTo(a.width);
    });
  return list.take(3).toList();
}

/// يرجع null إذا كانت الصورة غير مناسبة (موديل آخر، لقطة داخلية، حادث...).
double? scoreCandidate(String title, int width, int height, String mime,
    String brand, String model, String year) {
  final String t = title.toLowerCase();
  final String brandKey = brand.toLowerCase().replaceAll('-', '');
  final String brandKeySpaced = brand.toLowerCase();

  final bool brandHit = t.contains(brandKeySpaced) ||
      t.contains(brandKey) ||
      (brandKey == 'mg' && RegExp(r'\bmg\b').hasMatch(t)) ||
      (brandKey == 'byd' && t.contains('byd')) ||
      (brandKey == 'gac' &&
          (t.contains('gac') ||
              t.contains('trumpchi') ||
              t.contains('gs3') ||
              t.contains('gs8'))) ||
      (brandKey == 'mg' && (t.contains('saic') || t.contains('roewe')));
  if (!brandHit) return null;
  if (RegExp(r'\b(mg)\s?5\b').hasMatch(t) && brandKey != 'mg') return null;

  for (final bad in const [
    'interior',
    'cockpit',
    'dashboard',
    'steering',
    'engine',
    'gearbox',
    'transmission',
    'wheel',
    'tyre',
    'tire',
    'alloy',
    'badge',
    'emblem',
    'grille',
    'headlight',
    'headlamp',
    'taillight',
    'mirror',
    'seat',
    'leather',
    'screen',
    'display',
    'suspension',
    'chassis',
    'engine bay',
    'boot',
    'trunk',
    'panel',
    'detail',
    'close-up',
    'closeup',
    'logo',
    'sketch',
    'drawing',
    'blueprint',
    'crash',
    'accident',
    'wreck',
    'damaged',
    'broken',
    'police',
    'taxi',
    'ambulance',
    'fire',
    'military',
    'race',
    'racing',
    'track',
    'rally',
    'offroad',
    'prototype',
    'spy',
    'test drive',
    'ambulance',
    'carpet',
    'carpet',
    'licence plate',
    'license plate',
    'number plate',
  ]) {
    if (t.contains(bad)) return null;
  }

  final List<String> tokens = modelTokens(brand, model);
  bool modelHit = false;
  for (final token in tokens) {
    if (t.contains(token)) {
      modelHit = true;
      break;
    }
  }
  if (!modelHit) return null;
  // موديل رقمي (MG 5 / Mazda 6) قد يتكرر في اسم ملف لا علاقة له بالموديل.
  if (tokens.every((token) => token.length <= 2) &&
      !t.contains(model.toLowerCase())) {
    return null;
  }

  if (width < 1500 || height < 900) return null;

  double score = 0;
  if (RegExp(r'(^|[^a-z])3\s?/\s?4').hasMatch(t) || t.contains('quarter')) {
    score += 60;
  }
  if (t.contains('front')) score += 45;
  if (t.contains('side')) score += 12;
  if (t.contains('rear') || t.contains('back')) score -= 30;
  if (t.contains('profile')) score += 6;
  if (t.contains('isolated') ||
      t.contains('background') ||
      t.contains('cutout') ||
      t.contains('studio')) {
    score += 40;
  }
  if (mime == 'image/png') score += 28;
  if (t.contains('white')) score += 14;
  if (t.contains('grey') || t.contains('gray') || t.contains('silver')) {
    score += 8;
  }
  if (t.contains('show') || t.contains('autosalon') || t.contains('expo')) {
    score += 8;
  }
  if (year.isNotEmpty && t.contains(year)) score += 18;
  if (RegExp(r'\b(19|20)\d{2}\b').hasMatch(t)) score += 6;

  final double ar = width / height;
  if (ar < 1.2) score -= 30;
  if (ar > 2.1) score -= 20;
  if (ar >= 1.3 && ar <= 1.5) score += 14;

  for (final token in tokens) {
    if (token.length > 3 && t.contains(token)) score += 12;
  }
  score += math.min(width, 6000) / 6000 * 10;
  return score;
}

List<String> modelTokens(String brand, String model) {
  final String m = model.toLowerCase();
  final List<String> tokens = <String>[];
  final RegExpMatch? suffix =
      RegExp(r'\s(hev|phev|hybrid|ev|pro|max|plus|ace)$').firstMatch(m);
  var head = m;
  if (suffix != null) {
    head = m.substring(0, suffix.start);
    tokens.add(suffix.group(1)!);
  }
  for (final part in head.split(RegExp(r'[\s-]+'))) {
    if (part.isEmpty) continue;
    if (RegExp(r'^\d+$').hasMatch(part) && part.length <= 1) continue;
    tokens.add(part);
  }
  // بديل بدون مسافات للموديلات مثل mg5 / mazda6 / bmw320i
  tokens.add(head.replaceAll(RegExp(r'[\s-]+'), ''));
  return tokens.where((t) => t.isNotEmpty).toList();
}

// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// pin: تثبيت الصور من overrides.json على نتيجة الاختيار الحالية
// (يحذف الصورة القديمة من out/ حتى تُعاد من جديد في build)
// ---------------------------------------------------------------------------

Future<void> cmdPin() async {
  final pickedFile = File('$dir/picked.json');
  final picked =
      jsonDecode(pickedFile.readAsStringSync()) as Map<String, dynamic>;
  final rows = (picked['rows'] as List<dynamic>).cast<Map<String, dynamic>>();
  final chosen = (picked['chosen'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()));
  final overrides = readOverrides();

  var changed = 0;
  for (final entry in overrides.entries) {
    final current = chosen[entry.key]?.join('|');
    if (current == entry.value.join('|')) continue;
    chosen[entry.key] = entry.value;
    for (int i = 0; i < rows.length; i++) {
      if (rowKey(rows[i]) != entry.key) continue;
      final file = File('$outDir/${_fileName(i, rows[i])}');
      if (file.existsSync()) file.deleteSync();
    }
    stdout.writeln('ثُبّت ${entry.key} <- ${entry.value.first}');
    changed++;
  }

  pickedFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
    'rows': rows,
    'chosen': chosen,
  }));
  stdout.writeln('تثبيت: $changed موديل (أعد build لتحديث الصور)');
}

// ---------------------------------------------------------------------------
// build: تنزيل الصور وتوحيد الإضاءة وبناء لوحة معاينة لكل 30 سيارة
// ---------------------------------------------------------------------------

Future<void> cmdBuild(List<String> args) async {
  final bool restart = args.contains('--restart');
  final picked = jsonDecode(File('$dir/picked.json').readAsStringSync())
      as Map<String, dynamic>;
  final rows = (picked['rows'] as List<dynamic>).cast<Map<String, dynamic>>();
  final chosen = (picked['chosen'] as Map<String, dynamic>).map(
      (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()));

  Directory(outDir).createSync(recursive: true);
  final sheets = <img.Image>[];
  final sheetMeta = <List<String>>[];
  final entries = <({int index, Map<String, dynamic> row, img.Image image})>[];
  var skipped = 0;

  for (int i = 0; i < rows.length; i++) {
    final row = rows[i];
    final key = rowKey(row);
    final files = chosen[key];
    if (files == null || files.isEmpty) {
      skipped++;
      continue;
    }
    final outFile = File('$outDir/${_fileName(i, row)}');
    if (!restart && outFile.existsSync() && outFile.lengthSync() > 0) {
      final cached = img.decodeImage(outFile.readAsBytesSync());
      if (cached != null) {
        entries.add((index: i, row: row, image: cached));
        continue;
      }
    }
    final bytes = await downloadCommons(files.first);
    if (bytes == null) {
      stdout.writeln('[$i] ${_label(row)} <- فشل التنزيل ${files.first}');
      skipped++;
      continue;
    }
    final normalized = normalizePhoto(bytes);
    if (normalized == null) {
      stdout.writeln('[$i] ${_label(row)} <- فشل فك الترميز');
      skipped++;
      continue;
    }
    final double contrast = _lumaStdDev(normalized);
    if (contrast < 8) {
      // صورة مسطّحة (لون واحد) = ملف فاسد على كومنز، لا تُكتب ولا تُرفع.
      stdout.writeln('[$i] ${_label(row)} <- مسطّحة، تُتجاهل '
          '(${files.first})');
      skipped++;
      continue;
    }
    outFile.writeAsBytesSync(img.encodeJpg(
      normalized,
      quality: jpgQuality,
    ));
    entries.add((index: i, row: row, image: normalized));
    stdout.writeln('[$i] ${_label(row)} <- ${_photoStats(normalized)}');
  }

  // لوحة معاينة: 5 أعمدة × 6 صفوف لكل 30 صورة، مع رقم الفهرس فوق كل صورة.
  const int cols = 5;
  const int rowsPerSheet = 6;
  const int tileW = 340;
  const int tileH = 255;
  for (var start = 0; start < entries.length; start += cols * rowsPerSheet) {
    final chunk = entries.sublist(
        start, math.min(start + cols * rowsPerSheet, entries.length));
    final sheet = img.Image(width: cols * tileW, height: rowsPerSheet * tileH);
    img.fill(sheet, color: img.ColorRgb8(245, 245, 247));
    final labels = <String>[];
    for (var k = 0; k < chunk.length; k++) {
      final col = k % cols;
      final row = k ~/ cols;
      final x = col * tileW;
      final y = row * tileH;
      final tile = img.copyResize(chunk[k].image, width: tileW - 8);
      img.compositeImage(tile, sheet, dstX: x + 4, dstY: y + 20);
      final chip = img.Image(width: 46, height: 18);
      img.fill(chip, color: img.ColorRgb8(139, 13, 37));
      _drawDigits(chip, chunk[k].index, 2, 3);
      img.compositeImage(chip, sheet, dstX: x + 4, dstY: y + 2);
      labels.add('${chunk[k].index}: ${_label(chunk[k].row)}');
    }
    sheets.add(sheet);
    sheetMeta.add(labels);
  }

  for (var s = 0; s < sheets.length; s++) {
    File('$dir/sheet_${s + 1}.jpg')
        .writeAsBytesSync(img.encodeJpg(sheets[s], quality: 88));
    File('$dir/sheet_${s + 1}.txt').writeAsStringSync(sheetMeta[s].join('\n'));
  }
  stdout.writeln('صور موحّدة: ${entries.length}  متجاهَلة: $skipped');
  stdout.writeln('لوحات المعاينة: ${sheets.length} في $dir');
}

/// موحّد الإضاءة: قصّ 4:3، مقاس ثابت، توازن أبيض (grey world)، ثم ضبط
/// سطوع وتباين وإشباع نحو نفس القيم لكل الصور حتى تبدو زوايا الإضاءة متشابهة.
img.Image? normalizePhoto(Uint8List bytes) {
  var decoded = img.decodeImage(bytes);
  if (decoded == null) return null;

  // شفافية → أبيض
  if (decoded.numChannels == 4) {
    final flat = img.Image(width: decoded.width, height: decoded.height);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(decoded, flat);
    decoded = flat;
  }

  // قصّ 4:3 حول مركز الصورة مع رفع المركز قليلاً (السيارة تحت الأفق قليلاً)
  final sourceAspect = decoded.width / decoded.height;
  int cropW;
  int cropH;
  if (sourceAspect > outAspect) {
    cropH = decoded.height;
    cropW = (cropH * outAspect).round();
  } else {
    cropW = decoded.width;
    cropH = (cropW / outAspect).round();
  }
  cropW = math.min(cropW, decoded.width);
  cropH = math.min(cropH, decoded.height);
  final cropX = ((decoded.width - cropW) / 2).round();
  final cropY = ((decoded.height - cropH) * 0.46).round();
  var cropped =
      img.copyCrop(decoded, x: cropX, y: cropY, width: cropW, height: cropH);

  cropped = img.copyResize(cropped,
      width: outWidth,
      height: outHeight,
      interpolation: img.Interpolation.cubic);
  return balanceLight(cropped);
}

const double targetLuma = 128;
const double targetContrast = 1.0;
const double targetSaturation = 1.02;

img.Image balanceLight(img.Image src) {
  // القياس على نسخة صغيرة ثم تطبيق نفس المعاملات على الصورة كاملة.
  final small = img.copyResize(src, width: 160);
  double sumR = 0;
  double sumG = 0;
  double sumB = 0;
  double sumLuma = 0;
  double sumLuma2 = 0;
  var count = 0;
  for (final pixel in small) {
    final num r = pixel.r;
    final num g = pixel.g;
    final num b = pixel.b;
    sumR += r.toDouble();
    sumG += g.toDouble();
    sumB += b.toDouble();
    final double luma = 0.299 * r + 0.587 * g + 0.114 * b;
    sumLuma += luma;
    sumLuma2 += luma * luma;
    count++;
  }
  if (count == 0) return src;

  final double meanR = sumR / count;
  final double meanG = sumG / count;
  final double meanB = sumB / count;
  final double meanLuma = sumLuma / count;
  final double variance = math.max(0, sumLuma2 / count - meanLuma * meanLuma);
  final double stdLuma = math.sqrt(variance);

  // توازن أبيض: متوسط القنوات الثلاث يصبح واحداً.
  final double gray = (meanR + meanG + meanB) / 3;
  final double gainR = gray / math.max(1, meanR);
  final double gainG = gray / math.max(1, meanG);
  final double gainB = gray / math.max(1, meanB);

  // تعريض: وسّط الإضاءة على الهدف، مع الحفاظ على نسبة التباين الأصلية
  // (±25% حول 1.0) حتى لا تصبح الصور المسطّحة أو المعتمة متشابهة.
  final double exposure =
      (targetLuma / math.max(12, meanLuma)).clamp(0.55, 1.9);
  double contrast = 1.0;
  if (stdLuma > 1) {
    contrast = (1.0 + (62 / stdLuma - 1.0) * 0.45).clamp(0.7, 1.6);
  }
  contrast = contrast * targetContrast;

  for (final pixel in src) {
    var r = pixel.r.toDouble();
    var g = pixel.g.toDouble();
    var b = pixel.b.toDouble();
    // توازن أبيض
    r *= gainR;
    g *= gainG;
    b *= gainB;
    // تعريض
    r *= exposure;
    g *= exposure;
    b *= exposure;
    // تباين حول منتصف المدى
    r = (r - 128) * contrast + 128;
    g = (g - 128) * contrast + 128;
    b = (b - 128) * contrast + 128;
    // إشباع خفيف
    final double luma = 0.299 * r + 0.587 * g + 0.114 * b;
    r = luma + (r - luma) * targetSaturation;
    g = luma + (g - luma) * targetSaturation;
    b = luma + (b - luma) * targetSaturation;
    pixel
      ..r = r.round().clamp(0, 255)
      ..g = g.round().clamp(0, 255)
      ..b = b.round().clamp(0, 255);
  }
  return src;
}

String _photoStats(img.Image image) {
  double sum = 0;
  var count = 0;
  for (final pixel in image) {
    sum += 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
    count++;
  }
  return 'متوسط الإضاءة ${(sum / count).round()}';
}

double _lumaStdDev(img.Image image) {
  double sum = 0;
  double sum2 = 0;
  var count = 0;
  for (final pixel in image) {
    final double luma = 0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b;
    sum += luma;
    sum2 += luma * luma;
    count++;
  }
  if (count == 0) return 0;
  final double mean = sum / count;
  return math.sqrt(math.max(0, sum2 / count - mean * mean));
}

Future<Uint8List?> downloadCommons(String title) async {
  // مقاس مصغّرة قياسي في ويكيميديا (1920) — المقاسات غير القياسية تُرفض
  // أحياناً بخطأ 429 لأنها تتطلب توليد نسخة جديدة.
  const int thumbWidth = 1920;
  final uri = Uri.parse(commonsApi).replace(queryParameters: {
    'action': 'query',
    'format': 'json',
    'titles': title,
    'prop': 'imageinfo',
    'iiprop': 'url|size|mime',
    'iiurlwidth': '$thumbWidth',
  });
  final res = await commonsGet(uri);
  if (res == null || res.statusCode != 200) return null;
  final pages =
      (jsonDecode(res.body) as Map<String, dynamic>)['query']?['pages'];
  if (pages == null) return null;
  final page =
      (pages as Map<String, dynamic>).values.first as Map<String, dynamic>;
  final info = (page['imageinfo'] as List<dynamic>?)?.firstOrNull;
  if (info == null) return null;
  final imageInfo = info as Map<String, dynamic>;
  final thumb = '${imageInfo['thumburl'] ?? imageInfo['url']}';
  var bytes = await commonsGet(Uri.parse(thumb));
  if (bytes == null || bytes.statusCode != 200 || bytes.bodyBytes.isEmpty) {
    // بعض الملفات لا تقبل توليد نسخة مصغّرة، فنجرب الملف الأصلي.
    final original = '${imageInfo['url']}';
    if (original != thumb) {
      bytes = await commonsGet(Uri.parse(original));
    }
  }
  if (bytes == null || bytes.statusCode != 200 || bytes.bodyBytes.isEmpty) {
    return null;
  }
  return bytes.bodyBytes;
}

// ---------------------------------------------------------------------------
// apply: تسجيل الدخول، رفع الصور، وتحديث جدول السيارات
// ---------------------------------------------------------------------------

Future<void> cmdApply(List<String> args) async {
  final only = intArg(args, '--only') ?? -1;
  final bool dryRun = args.contains('--dry-run');
  final String username = argValue(args, '--username') ??
      Platform.environment['MOTRI_USER'] ??
      _prompt('اسم المستخدم');
  final String password = argValue(args, '--password') ??
      Platform.environment['MOTRI_PASS'] ??
      _prompt('كلمة المرور');

  final token = await login(username, password);
  final accountId = await accountUid(token);
  stdout.writeln('تم تسجيل الدخول: $username ($accountId)');
  if (dryRun) {
    stdout.writeln('وضع التجربة: لن يُرفع شيء.');
  }

  final outFiles = Directory(outDir)
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.jpg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final picked = jsonDecode(File('$dir/picked.json').readAsStringSync())
      as Map<String, dynamic>;
  final rows = (picked['rows'] as List<dynamic>).cast<Map<String, dynamic>>();
  final indexById = <String, int>{
    for (int i = 0; i < rows.length; i++) '${rows[i]['id']}': i,
  };

  var applied = 0;
  var failed = 0;
  var skipped = 0;
  for (final file in outFiles) {
    final name = file.uri.pathSegments.last;
    final id = name.split('_').first;
    final index = indexById[id];
    if (index == null || (only >= 0 && index != only)) continue;
    final row = rows[index];
    final uid = '${row['user_id']}';
    if (uid != accountId) {
      stdout.writeln('تخطّي ${_label(row)}: السيارة لحساب آخر ($uid)');
      skipped++;
      continue;
    }
    final path = '$uid/$storageFolder/'
        '${_slug('${row['brand']}')}__${_slug('${row['model']}')}'
        '__${id.substring(0, 4)}.jpg';

    final bytes = file.readAsBytesSync();
    final url = '$supabaseUrl/storage/v1/object/public/$carsBucket/$path';
    if (dryRun) {
      stdout.writeln('سيُرفع ${_label(row)} ($path, '
          '${(bytes.length / 1024).round()} كيلوبايت)');
      applied++;
      continue;
    }
    try {
      final uploaded = await upload(bytes, path, token);
      if (!uploaded) {
        stdout.writeln('FAIL رفع $name');
        failed++;
        continue;
      }
      final updated = await updateCarImage('${row['id']}', url, token);
      if (!updated) {
        stdout.writeln('FAIL تحديث ${_label(row)}');
        failed++;
        continue;
      }
      final head = await http.head(Uri.parse(url));
      if (head.statusCode != 200) {
        stdout.writeln(
            'FAIL ${_label(row)}: الرابط العام HTTP ${head.statusCode}');
        failed++;
        continue;
      }
      stdout.writeln('OK ${_label(row)} -> $path');
      applied++;
    } catch (e) {
      stdout.writeln('FAIL ${_label(row)} $e');
      failed++;
    }
  }

  stdout.writeln('--- ملخص ---');
  stdout.writeln('مرفوعة: $applied  فاشلة: $failed  متجاهَلة: $skipped  '
      'ملفات: ${outFiles.length}');
}

Future<String> accountUid(String token) async {
  final res = await http.get(Uri.parse('$supabaseUrl/auth/v1/user'), headers: {
    'apikey': supabasePublishableKey,
    'Authorization': 'Bearer $token',
  });
  if (res.statusCode != 200) {
    throw StateError('تعذّر قراءة الحساب (${res.statusCode})');
  }
  return '${(jsonDecode(res.body) as Map<String, dynamic>)['id']}';
}

Future<String> login(String username, String password) async {
  final res = await http.post(
    Uri.parse('$supabaseUrl/functions/v1/login-with-username'),
    headers: {
      'apikey': supabasePublishableKey,
      'Authorization': 'Bearer $supabasePublishableKey',
      'Content-Type': 'application/json',
    },
    body: jsonEncode({'username': username, 'password': password}),
  );
  if (res.statusCode != 200) {
    throw StateError('فشل تسجيل الدخول (HTTP ${res.statusCode}): ${res.body}');
  }
  final body = jsonDecode(res.body) as Map<String, dynamic>;
  final token = body['access_token'];
  if (token == null) throw StateError('لا يوجد access_token في الرد');
  return '$token';
}

Future<bool> upload(Uint8List bytes, String path, String token) async {
  final uri = Uri.parse('$supabaseUrl/storage/v1/object/$carsBucket/$path');
  final res = await http.post(uri,
      headers: {
        'apikey': supabasePublishableKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'image/jpeg',
        'x-upsert': 'true',
      },
      body: bytes);
  if (res.statusCode >= 200 && res.statusCode < 300) return true;
  stdout.writeln('  storage HTTP ${res.statusCode}: ${res.body}');
  return false;
}

Future<bool> updateCarImage(String id, String url, String token) async {
  final uri = Uri.parse('$supabaseUrl/rest/v1/cars?id=eq.$id');
  final res = await http.patch(uri,
      headers: {
        'apikey': supabasePublishableKey,
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'Prefer': 'return=representation',
      },
      body: jsonEncode({
        'image_url': jsonEncode([url]),
        'images': [url],
      }));
  if (res.statusCode != 200) {
    stdout.writeln('  rest HTTP ${res.statusCode}: ${res.body}');
    return false;
  }
  final list = jsonDecode(res.body) as List<dynamic>;
  if (list.isEmpty) return false;
  final check = '${(list.first as Map<String, dynamic>)['image_url']}';
  return check.contains('/$storageFolder/');
}

// ---------------------------------------------------------------------------
// أدوات مساعدة
// ---------------------------------------------------------------------------

String rowKey(Map<String, dynamic> row) =>
    '${row['brand']}|${row['model']}|${row['year']}';

String _label(Map<String, dynamic> row) =>
    '${row['brand']} ${row['model']} ${row['year']}';

String _fileName(int index, Map<String, dynamic> row) =>
    '${index.toString().padLeft(2, '0')}_${_slug('${row['brand']}')}'
    '_${_slug('${row['model']}')}.jpg';

String _slug(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
    .replaceAll(RegExp(r'^_|_$'), '');

Map<String, List<String>> readOverrides() {
  final file = File('$dir/overrides.json');
  if (!file.existsSync()) return <String, List<String>>{};
  final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return data.map(
      (key, value) => MapEntry(key, (value as List<dynamic>).cast<String>()));
}

int? intArg(List<String> args, String name) {
  final value = argValue(args, name);
  return value == null ? null : int.tryParse(value);
}

String? argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}

String _prompt(String label) {
  stdout.write('$label: ');
  final line = stdin.readLineSync() ?? '';
  stdout.writeln();
  return line.trim();
}

/// أرقام بسيطة (3×5) لكتابة رقم الفهرس على لوحة المعاينة بلا خطوط نظام.
const List<List<String>> _digits = [
  ['111', '101', '101', '101', '111'],
  ['010', '110', '010', '010', '111'],
  ['111', '001', '111', '100', '111'],
  ['111', '001', '111', '001', '111'],
  ['101', '101', '111', '001', '001'],
  ['111', '100', '111', '001', '111'],
  ['111', '100', '111', '101', '111'],
  ['111', '001', '010', '010', '010'],
  ['111', '101', '111', '101', '111'],
  ['111', '101', '111', '001', '111'],
];

void _drawDigits(img.Image canvas, int value, int x, int y) {
  final text = '$value';
  for (var i = 0; i < text.length; i++) {
    final digit = int.parse(text[i]);
    final glyph = _digits[digit];
    for (var row = 0; row < glyph.length; row++) {
      for (var col = 0; col < glyph[row].length; col++) {
        if (glyph[row][col] != '1') continue;
        img.fillRect(canvas,
            x1: x + i * 8 + col,
            y1: y + row,
            x2: x + i * 8 + col + 1,
            y2: y + row + 1,
            color: img.ColorRgb8(255, 255, 255));
      }
    }
  }
}
