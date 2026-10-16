/// Swift text semantics needed for fidelity: `CharacterSet.whitespacesAndNewlines` trimming,
/// `Character.isWhitespace` splitting and case/diacritic folding.
library;

import 'fold_table.g.dart';

/// `CharacterSet.whitespacesAndNewlines` as observed in Swift (fixtures): Zs, tab, newlines,
/// U+0085, U+2028/U+2029 and U+200B. U+FEFF is not whitespace.
bool isSwiftTrimmable(int r) =>
    r == 0x09 ||
    (r >= 0x0A && r <= 0x0D) ||
    r == 0x20 ||
    r == 0x85 ||
    r == 0xA0 ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200B) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202F ||
    r == 0x205F ||
    r == 0x3000;

/// Unicode `White_Space` (Swift `Character.isWhitespace`).
bool isSwiftWhitespace(int r) =>
    (r >= 0x09 && r <= 0x0D) ||
    r == 0x20 ||
    r == 0x85 ||
    r == 0xA0 ||
    r == 0x1680 ||
    (r >= 0x2000 && r <= 0x200A) ||
    r == 0x2028 ||
    r == 0x2029 ||
    r == 0x202F ||
    r == 0x205F ||
    r == 0x3000;

/// `text.trimmingCharacters(in: .whitespacesAndNewlines)`.
String swiftTrim(String text) {
  final runes = text.runes.toList();
  var start = 0, end = runes.length;
  while (start < end && isSwiftTrimmable(runes[start])) {
    start++;
  }
  while (end > start && isSwiftTrimmable(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

/// `text.split(whereSeparator: \.isWhitespace)` (empty pieces dropped).
List<String> splitOnWhitespace(String text) {
  final parts = <String>[];
  final current = StringBuffer();
  for (final r in text.runes) {
    if (isSwiftWhitespace(r)) {
      if (current.isNotEmpty) parts.add(current.toString());
      current.clear();
    } else {
      current.writeCharCode(r);
    }
  }
  if (current.isNotEmpty) parts.add(current.toString());
  return parts;
}

bool _isCombiningMark(int r) =>
    (r >= 0x0300 && r <= 0x036F) ||
    (r >= 0x0483 && r <= 0x0489) ||
    (r >= 0x1AB0 && r <= 0x1AFF) ||
    (r >= 0x1DC0 && r <= 0x1DFF) ||
    (r >= 0x20D0 && r <= 0x20FF) ||
    (r >= 0xFE20 && r <= 0xFE2F);

/// Swift `folding(options: [.caseInsensitive, .diacriticInsensitive], locale: es_AR)`:
/// the per-character table generated from Swift covers Latin, Greek and Cyrillic; combining marks
/// of Latin/Greek/Cyrillic and symbols (decomposed accents; Swift keeps Hebrew/Arabic vowel marks) are removed; anything else is lower-cased.
String foldDiacritics(String s) {
  final buffer = StringBuffer();
  for (final r in s.runes) {
    if (_isCombiningMark(r)) continue;
    final mapped = swiftFoldTable[r];
    buffer.write(mapped ?? String.fromCharCode(r).toLowerCase());
  }
  return buffer.toString();
}
