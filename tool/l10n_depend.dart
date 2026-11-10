// يضيف `context.dependOnAppStrings()` إلى كل `build` يقرأ `t('…')`.
//
// لماذا
// -----
// استدعاء `t()` ينفَّذ داخل `build()` لأي عنصر. إن لم يسجّل ذلك العنصر
// اعتماده على `AppStringsScope`، فلن يُعاد بناؤه عند تبديل اللغة، وتبقى
// النصوص العربية معروضة رغم أن `t()` يعيد الكردية. هذا الملف يجعل
// التسجيل قاعدة آلية بدل تذكّر يدوي.
//
// التشغيل: dart run tool/l10n_depend.dart [--check]

import 'dart:io';

void main(List<String> args) {
  final bool checkOnly = args.contains('--check');

  for (final String path in <String>['lib/main.dart', 'lib/market_images.dart']) {
    final List<String> lines = File(path).readAsLinesSync();
    final List<String> out = <String>[];
    int added = 0;
    int skipped = 0;

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      out.add(line);

      final RegExp buildRe =
          RegExp(r'^(\s*)Widget build\(BuildContext context\)\s*\{\s*$');
      final RegExpMatch? m = buildRe.firstMatch(line);
      if (m == null) continue;

      final String indent = m.group(1)!;

      // نهاية الكتلة: أول `build` تالٍ أو `class` أو إغلاق بنفس العمق.
      int end = lines.length;
      for (int j = i + 1; j < lines.length; j++) {
        if (RegExp(r'^\s*Widget build\(BuildContext').hasMatch(lines[j])) {
          end = j;
          break;
        }
        if (RegExp(r'^\s*class\s').hasMatch(lines[j])) {
          end = j;
          break;
        }
        if (lines[j] == '$indent}') {
          end = j;
          break;
        }
      }

      bool usesT = false;
      bool already = false;
      for (int j = i + 1; j < end; j++) {
        if (RegExp(r"\bt\('").hasMatch(lines[j])) usesT = true;
        if (lines[j].contains('dependOnAppStrings')) already = true;
      }

      if (!usesT) continue;
      if (already) {
        skipped++;
        continue;
      }
      out.add('$indent  // تجيل الاعتماد على اللغة: هذا `build` يقرأ `t()`.');
      out.add('$indent  context.dependOnAppStrings();');
      added++;
    }

    if (!checkOnly && added > 0) {
      File(path).writeAsStringSync('${out.join('\n')}\n');
    }
    stdout.writeln('$path -> added $added, already $skipped');
  }
}
