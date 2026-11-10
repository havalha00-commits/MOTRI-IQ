// Verifies that adding the English column changed no Arabic or Kurdish literal.
//
// Compares the pre-change backup against the current file entry by entry:
// same keys in the same order, and the key/ar/ku argument text identical up to
// where the new English argument was appended.
//
// Usage: dart run tool/verify_ar_ku_unchanged.dart

import 'dart:io';

const String current =
    r'C:\Users\hp\Desktop\MOTRI-IQ-clean-project\lib\l10n\app_strings.dart';
const String backup =
    r'C:\Users\hp\AppData\Local\Temp\kilo\app_strings_before_en.dart';

class Entry {
  Entry(this.key, this.args);
  final String key;
  final String args;
}

void main() {
  final List<Entry> now = parse(File(current).readAsStringSync());
  final List<Entry> before = parse(File(backup).readAsStringSync());

  if (now.length != before.length) {
    stderr.writeln('entry count changed: ${before.length} -> ${now.length}');
    exit(2);
  }

  int bad = 0;
  for (int i = 0; i < now.length; i++) {
    if (now[i].key != before[i].key) {
      stdout.writeln('KEY ORDER CHANGED at index $i: '
          '"${before[i].key}" -> "${now[i].key}"');
      bad++;
      continue;
    }
    // Everything before the appended English argument must be unchanged. The
    // inserted text always starts with ", " followed by a quote.
    final String args = now[i].args;
    final int cut = _englishStart(args);
    if (cut < 0) {
      stdout.writeln('NO ENGLISH ARGUMENT for "${now[i].key}"');
      bad++;
      continue;
    }
    final String head = args.substring(0, cut);
    if (head != before[i].args) {
      stdout.writeln('AR/KU CHANGED for "${now[i].key}"');
      stdout.writeln('  before: ${before[i].args}');
      stdout.writeln('  now:    $head');
      bad++;
    }
  }

  if (bad == 0) {
    stdout.writeln('AR_KU_IDENTICAL_ACROSS_${now.length}_ENTRIES');
  } else {
    stdout.writeln('$bad entr(y/ies) differ');
    exit(2);
  }
}

/// Offset of the ", " that precedes the English argument, scanning backwards
/// from the closing paren and ignoring commas inside string literals.
int _englishStart(String args) {
  bool inString = false;
  final List<int> commas = <int>[];
  for (int i = 0; i < args.length; i++) {
    final String ch = args[i];
    if (inString) {
      if (ch == r'\') {
        i++;
      } else if (ch == "'") {
        inString = false;
      }
    } else if (ch == "'") {
      inString = true;
    } else if (ch == ',') {
      commas.add(i);
    }
  }
  if (commas.isEmpty) return -1;
  return commas.last;
}

bool _isSpace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

List<Entry> parse(String source) {
  const String marker = 'AppStringEntry(';
  final List<Entry> out = <Entry>[];
  int i = 0;
  while (true) {
    final int at = source.indexOf(marker, i);
    if (at < 0) break;
    final int lineStart = source.lastIndexOf('\n', at - 1) + 1;
    final String prefix = source.substring(lineStart, at);
    int probe = at + marker.length;
    while (probe < source.length && _isSpace(source.codeUnitAt(probe))) {
      probe++;
    }
    // Skip the constructor declaration and commented-out mentions: a real entry
    // opens with a quote immediately after the marker.
    if (prefix.contains('//') ||
        probe >= source.length ||
        source[probe] != "'") {
      i = at + marker.length;
      continue;
    }
    int p = at + marker.length;
    while (source[p] != "'") {
      p++;
    }
    final int keyEnd = source.indexOf("'", p + 1);
    final String key = source.substring(p + 1, keyEnd);

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
    out.add(Entry(key, source.substring(keyEnd + 1, j)));
    i = j + 1;
  }
  return out;
}
