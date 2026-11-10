// فحص تغطية الترجمة: أي نصوص عربية في الواجهة لم تُدخَل بعد في جدول
// `appStringEntries`؟
//
// التشغيل: dart run tool/l10n_coverage.dart

import 'dart:io';

import 'package:motri_iq/l10n/app_strings.dart';

/// قيم مخزَّنة في Supabase أو تُقارَن حرفيًا. لا يجوز ترجمتها وإلا
/// انكسرت الفلترة والمقارنات.
const Set<String> dataValues = <String>{
  // المحافظات
  'بغداد', 'البصرة', 'أربيل', 'السليمانية', 'دهوك', 'نينوى', 'كركوك',
  'الأنبار', 'ديالى', 'صلاح الدين', 'واسط', 'بابل', 'كربلاء', 'النجف',
  'القادسية', 'ذي قار', 'ميسان', 'المثنى',
  // أنواع الهيكل
  'سيدان', 'SUV', 'هاتشباك', 'بيك أب', 'كوبيه', 'فان',
  // علامات تجارية وأمثلة
  'CARFAX', 'motri_user', 'د.ع',
};

String stripComments(String source) {
  final StringBuffer out = StringBuffer();
  bool inBlock = false;
  for (final String line in source.split('\n')) {
    String result = '';
    int i = 0;
    while (i < line.length) {
      if (inBlock) {
        final int end = line.indexOf('*/', i);
        if (end == -1) {
          i = line.length;
        } else {
          inBlock = false;
          i = end + 2;
        }
        continue;
      }
      if (line.startsWith('//', i)) break;
      if (line.startsWith('/*', i)) {
        inBlock = true;
        i += 2;
        continue;
      }
      result += line[i];
      i++;
    }
    out.writeln(result);
  }
  return out.toString();
}

Map<String, List<int>> harvest(String path) {
  final String source = stripComments(File(path).readAsStringSync());
  final RegExp re = RegExp(r"(r?)'((?:\\.|[^'\\\r\n])*)'");
  final Map<String, List<int>> map = <String, List<int>>{};
  final List<String> lines = source.split('\n');
  for (int i = 0; i < lines.length; i++) {
    for (final RegExpMatch m in re.allMatches(lines[i])) {
      final String body = (m.group(2) ?? '').replaceAll(r"\'", "'");
      if (!body.contains(RegExp(r'[\u0600-\u06FF]'))) continue;
      map.putIfAbsent(body, () => <int>[]).add(i + 1);
    }
  }
  // ترميز الموقع كرقم سطر داخل الملف مع اسم الملف في الخريطة الرئيسية.
  return map.map((String k, List<int> v) =>
      MapEntry<String, List<int>>(k, v)); // placeholder
}

String locationOf(String file, int line) => '$file:$line';

/// يوحّد المسافات الطارئة والداخلية حتى لا يُحسَب اختلافٌ شكليٌّ
/// (مسافة زائدة مثلًا) نقصًا في التغطية.
String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final Map<String, String> covered = <String, String>{
    for (final AppStringEntry e in appStringEntries) norm(e.ar): e.key,
  };

  final Map<String, List<int>> all = <String, List<int>>{};
  final Map<String, String> where = <String, String>{};
  for (final String f in <String>['lib/main.dart', 'lib/market_images.dart']) {
    final String name = f.split('/').last;
    harvest(f).forEach((String k, List<int> v) {
      all.putIfAbsent(k, () => <int>[]).addAll(v);
      where.putIfAbsent(k, () => '$name:${v.first}');
    });
  }

  final List<String> missing = <String>[];
  final List<String> dataSkipped = <String>[];

  for (final String s in all.keys) {
    if (covered.containsKey(norm(s))) continue;
    if (dataValues.contains(s)) {
      dataSkipped.add(s);
      continue;
    }
    // نص داخل استبدال (interpolation) لا يُغطّى بالنص الحرفي.
    if (s.contains(r'${') || s.contains('\$')) continue;
    missing.add(s);
  }

  missing.sort((String a, String b) => a.compareTo(b));

  stdout.writeln('total distinct : ${all.length}');
  stdout.writeln('covered        : ${all.keys.where(covered.containsKey).length}');
  stdout.writeln('data (skipped) : ${dataSkipped.length}');
  stdout.writeln('MISSING        : ${missing.length}\n');

  int i = 0;
  for (final String s in missing) {
    i++;
    stdout.writeln('${i.toString().padLeft(3)}  '
        '${where[s]}  ${s.replaceAll('\n', r'\n')}');
  }

  stdout.writeln('\n--- data values skipped (never translate) ---');
  stdout.writeln(dataSkipped.join('  '));
}
