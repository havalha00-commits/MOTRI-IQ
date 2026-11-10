// تحويل النصوص العربية الثابتة في الواجهة إلى استدعاءات `t('key')`.
//
// Safety model
// ------------
// * لا يستبدل شيئًا داخل كتل البيانات (المحافظات، أنواع الهيكل) لأنها قيم
//   مخزَّنة تُقارَن حرفيًا.
// * يدمج النصوص المتجاورة (adjacent literals) التي يجمعها Dart تلقائيًا
//   قبل Lookup، حتى لا تنقسم ترجمة واحدة إلى شطرين.
// * أي نص لا يجد مفتاحًا له يُترك كما هو ويُبلّغ عنه، فلا يُحذف نص ولا
//   يُستبدل بسلسلة فارغة.
// * dry-run افتراضي؛ `--apply` هو ما يكتب فعلًا.
//
// التشغيل: dart run tool/l10n_codemod.dart [--apply]

import 'dart:io';

import 'package:motri_iq/l10n/app_strings.dart';

/// أسطر كتل البيانات التي لا يجوز لمسها.
const Map<String, List<int>> dataLineRanges = <String, List<int>>{
  // main.dart: iraqiProvinces + vehicleBodyTypes
  'lib/main.dart': <int>[244, 275],
};

/// شظايا نصوص ليست نصوص واجهة (أجزاء استبدال أو فواصل).
const Set<String> fragments = <String>{
  '، ',
  ']} دولار',
  '} دولار',
  ': ',
  ' صورة',
  ' يوم',
  ' شهر',
  'Photos',
};

String norm(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// يزيل التعليقات مع الحفاظ على ترتيب الأسطر.
///
/// مهم: يجب تتبّع حالة السلسلة النصية داخل السطر، وإلا قُطعت الروابط
/// مثل `'https://…'` عند `//` وحُدّثت إلى `'https:`.
List<String> stripComments(List<String> lines) {
  final List<String> out = <String>[];
  bool inBlock = false;
  for (final String line in lines) {
    String result = '';
    int i = 0;
    bool inString = false;
    while (i < line.length) {
      final String c = line[i];
      if (inString) {
        result += c;
        if (c == r'\' && i + 1 < line.length) {
          result += line[i + 1];
          i += 2;
          continue;
        }
        if (c == "'") inString = false;
        i++;
        continue;
      }
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
      if (c == "'") {
        inString = true;
        result += c;
        i++;
        continue;
      }
      if (line.startsWith('//', i)) break;
      if (line.startsWith('/*', i)) {
        inBlock = true;
        i += 2;
        continue;
      }
      result += c;
      i++;
    }
    out.add(result);
  }
  return out;
}

/// يعيد قائمة ببدايات النصوص وأطوالها داخل سطر واحد.
List<({int start, int end, String body, bool raw})> literalsIn(String line) {
  final List<({int start, int end, String body, bool raw})> found =
      <({int start, int end, String body, bool raw})>[];
  int i = 0;
  while (i < line.length) {
    if (line.startsWith("'", i) && !(i > 0 && _isIdentChar(line[i - 1]))) {
      int j = i + 1;
      final StringBuffer body = StringBuffer();
      while (j < line.length) {
        if (line[j] == r'\' && j + 1 < line.length) {
          body.write(line[j]);
          body.write(line[j + 1]);
          j += 2;
          continue;
        }
        if (line[j] == "'") break;
        body.write(line[j]);
        j++;
      }
      if (j < line.length) {
        found.add((start: i, end: j + 1, body: body.toString(), raw: false));
        i = j + 1;
        continue;
      }
    }
    i++;
  }
  return found;
}

bool _isIdentChar(String c) =>
    RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

bool hasArabic(String s) => RegExp(r'[\u0600-\u06FF]').hasMatch(s);

/// `t()` تقرأ حالة وقت التشغيل، فلا تصلح داخل `const`.
///
/// يعثر على كل كلمة `const` ويحدد التعبير الذي تسبقه (قائمة أو مُنشئ)،
/// فإن كان يحتوي استدعاء `t(` تُحذف الكلمة. تُعالَج المواضع من آخرها إلى
/// أولها حتى لا تتغيّر الإزاحات قبلها.
String stripConstWrappingT(String code) {
  final List<int> positions = RegExp(r'\bconst\s+')
      .allMatches(code)
      .map((RegExpMatch m) => m.start)
      .toList();

  for (final int pos in positions.reversed) {
    final String after = code.substring(pos + 5);
    final String trimmed = after.trimLeft();
    final int gap = after.length - trimmed.length;
    int i = pos + 5 + gap;
    if (i >= code.length) continue;

    String? open;
    int bracketAt = -1;
    bool isDeclaration = false;

    final String first = code[i];
    if (first == '[' || first == '{' || first == '(') {
      open = first;
      bracketAt = i;
    } else {
      // يتخطّى اسم النوع ثم المعاملات العامة ثم `=` إن وُجدت، ليصل إلى
      // القوس الذي يحمل التعبير المقيَّم فعليًا.
      int j = i;
      while (j < code.length) {
        // `=` يعلن تصريح متغيّر: يُستبدل `const` بـ`final` ولا يُحذف.
        if (code[j] == '=') {
          j++;
          while (j < code.length && RegExp(r'\s').hasMatch(code[j])) {
            j++;
          }
          isDeclaration = true;
          continue;
        }
        if (RegExp(r'[A-Za-z0-9_$<>,\s]').hasMatch(code[j])) {
          // معاملات عامة مثل `List<(String, String)>` قد تحوي أقواسًا.
          if (code[j] == '<') {
            final int after = _skipGeneric(code, j);
            if (after < 0) break;
            j = after;
            continue;
          }
          j++;
          continue;
        }
        break;
      }
      if (j < code.length && (code[j] == '[' || code[j] == '{' || code[j] == '(')) {
        open = code[j];
        bracketAt = j;
      }
    }

    if (open == null || bracketAt < 0) continue;
    final String close = open == '[' ? ']' : (open == '{' ? '}' : ')');
    final int end = _matchBracket(code, bracketAt, open, close);
    if (end < 0) continue;
    if (!code.substring(bracketAt, end).contains("t('")) continue;

    // تصريح متغيّر: `final` لا يحذف الاسم. مُنشئ أو قائمة: تُحذف الكلمة.
    if (isDeclaration) {
      code = '${code.substring(0, pos)}final ${code.substring(pos + 5)}';
    } else {
      code = '${code.substring(0, pos)}${code.substring(pos + 5)}';
    }
  }
  return code;
}

/// يتخطّى معاملًا عامًا `<...>` بما فيه الأقواس المتداخلة.
int _skipGeneric(String code, int start) {
  int depth = 0;
  for (int i = start; i < code.length; i++) {
    final String c = code[i];
    if (c == '<') depth++;
    if (c == '>') {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

/// يفهرس القوس المطابق لـ open ابتداءً من start.
int _matchBracket(String code, int start, String open, String close) {
  int depth = 0;
  bool inString = false;
  for (int i = start; i < code.length; i++) {
    final String c = code[i];
    if (inString) {
      if (c == r'\' && i + 1 < code.length) {
        i++;
        continue;
      }
      if (c == "'") inString = false;
      continue;
    }
    if (c == "'") {
      inString = true;
      continue;
    }
    if (c == open) depth++;
    if (c == close) {
      depth--;
      if (depth == 0) return i + 1;
    }
  }
  return -1;
}

void main(List<String> args) {
  final bool apply = args.contains('--apply');
  final Map<String, String> byAr = <String, String>{
    for (final AppStringEntry e in appStringEntries) norm(e.ar): e.key,
  };

  int replaced = 0;
  int skipped = 0;
  final List<String> unmapped = <String>[];

  for (final String path in <String>['lib/main.dart', 'lib/market_images.dart']) {
    final List<String> original = File(path).readAsLinesSync();
    final List<String> lines = stripComments(original);
final List<int> range =
        dataLineRanges[path] ?? const <int>[];
    final List<bool> blocked = List<bool>.generate(
      lines.length,
      (int i) => range.length == 2 && i + 1 >= range[0] && i + 1 <= range[1],
    );

    // دمج النصوص المتجاورة: سطر ينتهي بنص والسطر التالي يبدأ بنص.
    final List<String> out = <String>[];
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      int j = i;
      final List<({int start, int end, String body, bool raw})> groups =
          literalsIn(line).where((g) => g.end == line.length).toList();
      if (groups.length == 1 && !blocked[i] && hasArabic(groups[0].body)) {
        final StringBuffer combined = StringBuffer(groups[0].body);
        final List<int> consumed = <int>[i];
        j = i + 1;
        while (j < lines.length && !blocked[j]) {
          final String next = lines[j];
          final List<({int start, int end, String body, bool raw})> nl =
            literalsIn(next);
if (nl.length != 1) break;
          // يُقبل أن يسبق النص مسافات بادئة فقط (سطر تكملة).
          if (next.substring(0, nl.first.start).trim().isNotEmpty) break;
          if (!hasArabic(nl.first.body)) break;
          combined.write(nl.first.body);
          consumed.add(j);
          j++;
        }
if (consumed.length > 1) {
          final String? key = byAr[norm(combined.toString())];
          // ما قبل أول نص وما بعد آخر نص (فاصلة أو قوس) يجب البقاء كما هو.
          final String head = line.substring(0, groups[0].start);
          final int lastLine = consumed.last;
          final List<({int start, int end, String body, bool raw})> lastLits =
              literalsIn(lines[lastLine]);
          final String tail =
              lines[lastLine].substring(lastLits.last.end);
          if (key == null) {
            unmapped.add('$path:${i + 1} GROUP $norm(combined.toString())');
            skipped++;
          } else {
            line = "$head" "t('$key')" "$tail";
            replaced++;
          }
          // النص المدموج يحلّ محل السطر الأول، والأسطر اللاحقة تُفرَّغ.
          out.add(line);
          for (final int k in consumed) {
            if (k > i) out.add('');
          }
          i = j - 1;
          continue;
        }
      }

      if (!blocked[i]) {
        final List<({int start, int end, String body, bool raw})> ls =
            literalsIn(line);
        final StringBuffer rebuilt = StringBuffer();
        int last = 0;
        bool changed = false;
        for (final g in ls) {
          if (!hasArabic(g.body)) continue;
          final String n = norm(g.body);
          if (fragments.contains(n) || fragments.contains(g.body)) {
            continue;
          }
          final String? key = byAr[n];
if (key == null) {
            unmapped.add('$path:${i + 1} $n');
            skipped++;
            continue;
          }
          rebuilt.write(line.substring(last, g.start));
          rebuilt.write("t('$key')");
          last = g.end;
          changed = true;
          replaced++;
        }
        if (changed) {
          rebuilt.write(line.substring(last));
          line = rebuilt.toString();
        }
      }

      out.add(line);
    }

if (apply) {
      File(path).writeAsStringSync(stripConstWrappingT('${out.join('\n')}\n'));
      stdout.writeln('patched $path');
    }
  }

  stdout.writeln('replaced : $replaced');
  stdout.writeln('unmapped : $skipped');
  if (unmapped.isNotEmpty) {
    stdout.writeln('\n--- unmapped (left untouched) ---');
    for (final String u in unmapped) {
      stdout.writeln('  $u');
    }
  }
  stdout.writeln('\n${apply ? 'APPLIED' : 'DRY RUN — استخدم --apply للكتابة'}');
}
