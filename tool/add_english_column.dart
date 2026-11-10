// Adds an English argument to every AppStringEntry in lib/l10n/app_strings.dart.
//
// The Arabic and Kurdish literals are copied through byte-for-byte: this tool
// only inserts `, '<english>'` immediately before each entry's closing paren.
// It aborts if any key is missing from translations.tsv, so a partial
// translation can never reach the app.
//
// Usage: dart run tool/add_english_column.dart

import 'dart:io';

const String target =
    r'C:\Users\hp\Desktop\MOTRI-IQ-clean-project\lib\l10n\app_strings.dart';
const String translationsDir =
    r'C:\Users\hp\Desktop\MOTRI-IQ-clean-project\tool';

const String marker = 'AppStringEntry(';

/// Keys whose existing literal is a Dart raw string (`r'...'`). For these the
/// backslash must not be escaped, so `\n` stays two characters exactly as it
/// is in the Arabic value.
const Set<String> rawKeys = <String>{'report_body_prefix'};

String escapeDart(String text, {required bool raw}) {
  String out = text.replaceAll(r'\$', r'\$');
  if (!raw) {
    out = out.replaceAll(r'\', r'\\');
    out = out.replaceAll('\n', r'\n');
  }
  return out.replaceAll("'", r"\'");
}

/// Reads translations from `tool/translations.tsv`, one `key<TAB>text` per line.
/// Lines starting with `#` are comments. A missing file is treated as empty so
/// the tool reports every key as missing rather than throwing a file error.
Map<String, String> loadTranslations() {
  final Map<String, String> table = <String, String>{};
  final File file = File(translationsDir + r'\translations.tsv');
  if (!file.existsSync()) return table;
  for (final String raw in file.readAsLinesSync()) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final List<String> parts = raw.split('\t');
    if (parts.length < 2) {
      stderr.writeln('bad translation line (need a TAB): $raw');
      exit(2);
    }
    table[parts[0].trim()] = parts.sublist(1).join('\t');
  }
  return table;
}

void main() {
  final Map<String, String> table = loadTranslations();
  final String source = File(target).readAsStringSync();

  final StringBuffer out = StringBuffer();
  int i = 0;
  int count = 0;
  final List<String> missing = <String>[];

  while (i < source.length) {
    final int at = source.indexOf(marker, i);
    if (at < 0) {
      out.write(source.substring(i));
      break;
    }
    // The constructor declaration `AppStringEntry(this.key, ...)` and any
    // mention inside a comment are not entries; require the quote that
    // follows the marker to sit on the same line, which is how every entry
    // in the table is written.
    if (!_isEntry(source, at)) {
      out.write(source.substring(i, at + marker.length));
      i = at + marker.length;
      continue;
    }

    // Copy everything up to and including the marker.
    out.write(source.substring(i, at + marker.length));

    // The key is the first single-quoted literal after the marker.
    int p = at + marker.length;
    while (p < source.length && _isSpace(source.codeUnitAt(p))) {
      p++;
    }
    if (source[p] != "'") {
      throw StateError('expected a quoted key at offset $p');
    }
    final int keyEnd = source.indexOf("'", p + 1);
    final String key = source.substring(p + 1, keyEnd);

    // Copy the key literal through unchanged, then the remaining arguments.
    out.write(source.substring(at + marker.length, keyEnd + 1));

    // Scan from the marker to this entry's matching close paren, tracking
    // string state so parens and quotes inside literals are ignored.
    int depth = 1;
    int j = at + marker.length;
    bool inString = false;
    while (j < source.length && depth > 0) {
      final String ch = source[j];
      if (inString) {
        if (ch == r'\') {
          j += 2;
          continue;
        }
        if (ch == "'") inString = false;
      } else {
        if (ch == "'") {
          inString = true;
        } else if (ch == '(') {
          depth++;
        } else if (ch == ')') {
          depth--;
          if (depth == 0) break;
        }
      }
      j++;
    }
    if (depth != 0) {
      throw StateError('unbalanced parentheses for key "$key"');
    }

    // j is the index of the closing paren; copy the ar/ku arguments verbatim.
    out.write(source.substring(keyEnd + 1, j));

    if (!table.containsKey(key)) {
      missing.add(key);
    } else {
      final bool raw = rawKeys.contains(key);
      final String prefix = raw ? "r" : '';
      out.write(", $prefix'${escapeDart(table[key]!, raw: raw)}'");
      count++;
    }

    out.write(')');
    i = j + 1;
  }

  if (missing.isNotEmpty) {
    stderr.writeln('missing English for ${missing.length} keys:');
    for (final String key in missing) {
      stderr.writeln('  $key');
    }
    exit(2);
  }

  File(target).writeAsStringSync(out.toString());
  stdout.writeln('added English to $count entries');
}

/// True when the marker at [at] starts a real table entry, i.e. the first
/// non-space character after it is a quote on the same line and this is not
/// inside a `//` comment.
bool _isEntry(String source, int at) {
  int i = at + marker.length;
  while (i < source.length && _isSpace(source.codeUnitAt(i))) {
    i++;
  }
  if (i >= source.length) return false;
  // Walk back over the marker's line prefix to rule out a commented-out line.
  final int lineStart = source.lastIndexOf('\n', at - 1) + 1;
  if (source.substring(lineStart, at).contains('//')) return false;
  return source[i] == "'";
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;
