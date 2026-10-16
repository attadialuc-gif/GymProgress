// Embeds the iOS exercise library (GymCore/Sources/GymStore/Resources/exercises.json) into
// lib/src/catalog_data.g.dart. Run from crossplatform/gym_store: `dart run tool/gen_catalog.dart`.
import 'dart:convert';
import 'dart:io';

void main() {
  final source = File('../../GymCore/Sources/GymStore/Resources/exercises.json').readAsStringSync();
  // Re-encode compactly (and validate) so the Dart literal has no line noise.
  final compact = jsonEncode(jsonDecode(source));
  if (compact.contains("'''")) throw StateError('Unexpected triple quote in the catalog');
  File('lib/src/catalog_data.g.dart').writeAsStringSync(
    '// GENERATED from GymCore/Sources/GymStore/Resources/exercises.json (the iOS library).\n'
    '// Do not edit: regenerate with `dart run tool/gen_catalog.dart`.\n\n'
    "const String bundledCatalogJson = r'''$compact''';\n",
  );
  stdout.writeln('catalog_data.g.dart written (${compact.length} chars)');
}
