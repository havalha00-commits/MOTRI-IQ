// أداة جرد النصوص العربية الثابتة في `lib/main.dart`.
//
// تُخرج قائمة بالنصوص العربية الفريدة، مع عدد التكرارات ورقم أول سطر،
// بعد حذف التعليقات. الغرض: تحديد ما هو نص واجهة يستحق الترجمة وما هو
// بيانات (أسماء سيارات، علامات تجارية، قيم Supabase) أو مفاتيح توجيه
// داخلية لا يجوز ترجمتها.
//
// التشغيل: dart run tool/l10n_audit.dart

import 'dart:io';

const String target = 'lib/main.dart';

/// يحذف تعليقات `//` و `/* */` و_doc comments_ مع الحفاظ على رقم السطر.
String stripComments(String source) {
  final StringBuffer out = StringBuffer();
  final List<String> lines = source.split('\n');
  bool inBlock = false;

  for (final String line in lines) {
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

/// يستخرج نصوص Dart ذات علامات اقتباس مفردة، متجاهلًا `\'` و `r'`.
List<String> singleQuoted(String source) {
  final List<String> found = <String>[];
  final RegExp re = RegExp(r"(r?)'((?:\\.|[^'\\\r\n])*)'");
  for (final RegExpMatch m in re.allMatches(source)) {
    final String body = m.group(2) ?? '';
    if (body.contains(RegExp(r'[\u0600-\u06FF]'))) {
      found.add(body.replaceAll(r"\'", "'"));
    }
  }
  return found;
}

void main() {
  final String source = stripComments(File(target).readAsStringSync());
  final List<String> lines = source.split('\n');

  // رقم أول سطر لكل قيمة.
  final Map<String, int> firstLine = <String, int>{};
  final Map<String, int> count = <String, int>{};

  for (int i = 0; i < lines.length; i++) {
    for (final String s in singleQuoted(lines[i])) {
      count[s] = (count[s] ?? 0) + 1;
      firstLine.putIfAbsent(s, () => i + 1);
    }
  }

  // نصوص حامِلة للـ interpolation تُستبعد من القائمة التلقائية لأنها
  // ليست قيمًا ثابتة، وتُطبع منفصلة.
  final List<String> interpolated = count.keys
      .where((String k) => k.contains(r'${') || k.contains('\$'))
      .toList()
    ..sort();

  final List<String> plain = count.keys
      .where((String k) => !k.contains(r'${') && !k.contains('\$'))
      .toList()
    ..sort((String a, String b) {
      final int byCount = (count[b] ?? 0).compareTo(count[a] ?? 0);
      return byCount != 0 ? byCount : a.compareTo(b);
    });

  stdout.writeln('=== distinct Arabic literals: ${plain.length} '
      '(plain) / ${interpolated.length} (with interpolation) ===\n');

  int index = 0;
  for (final String s in plain) {
    index++;
    final String one = s.replaceAll('\n', r'\n');
    stdout.writeln('${index.toString().padLeft(3)}  '
        'x${(count[s] ?? 0).toString().padLeft(2)}  '
        'L${(firstLine[s] ?? 0).toString().padLeft(5)}  $one');
  }

  if (interpolated.isNotEmpty) {
    stdout.writeln('\n=== with interpolation (${interpolated.length}) ===');
    for (final String s in interpolated) {
      stdout.writeln('  x${count[s]}  L${firstLine[s]}  '
          '${s.replaceAll('\n', r'\n')}');
    }
  }
}
