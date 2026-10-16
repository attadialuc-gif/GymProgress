// Regenerates lib/src/fold_table.g.dart from the Swift fixture (../fixtures/parsing.json, "fold").
// Run from crossplatform/gym_core: `dart run tool/gen_fold_table.dart` (D-103).
import 'dart:convert';
import 'dart:io';

void main() {
  final fixture = jsonDecode(File('../fixtures/parsing.json').readAsStringSync()) as Map<String, Object?>;
  final rows = (fixture['fold'] as List).cast<Map<String, Object?>>();
  String literal(String s) {
    final b = StringBuffer("'");
    for (final r in s.runes) {
      final ch = String.fromCharCode(r);
      if (r >= 0x20 && r < 0x7F && !"\\'\$".contains(ch)) {
        b.write(ch);
      } else {
        b.write('\\u{${r.toRadixString(16).toUpperCase()}}');
      }
    }
    return (b..write("'")).toString();
  }

  final out = StringBuffer()
    ..writeln('// GENERATED from crossplatform/fixtures/parsing.json ("fold"), i.e. from Swift')
    ..writeln('// `String.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: es_AR)` run per')
    ..writeln('// character. Do not edit: regenerate with `dart run tool/gen_fold_table.dart` (D-103).')
    ..writeln()
    ..writeln('/// Scalar → folded text, only for scalars that change.')
    ..writeln('const Map<int, String> swiftFoldTable = {');
  for (final r in rows) {
    out.writeln('  0x${(r['c'] as int).toRadixString(16).toUpperCase()}: ${literal(r['folded'] as String)},');
  }
  out.writeln('};');
  File('lib/src/fold_table.g.dart').writeAsStringSync(out.toString());
  stdout.writeln('fold_table.g.dart: ${rows.length} entries');
}
