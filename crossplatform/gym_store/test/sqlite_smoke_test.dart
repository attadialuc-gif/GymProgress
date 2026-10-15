import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The native SQLite library is available to the store (bundled by the sqlite3 build hook).
void main() {
  test('SQLite opens, supports JSON and user_version migrations', () {
    final db = sqlite3.openInMemory();
    addTearDown(db.close);
    final version = db.select('SELECT sqlite_version() AS v').first['v'] as String;
    expect(int.parse(version.split('.').first), greaterThanOrEqualTo(3));
    db.execute('PRAGMA user_version = 7');
    expect(db.select('PRAGMA user_version').first.values.first, 7);
    expect(db.select("SELECT json_extract('{\"a\":62.5}', '\$.a') AS a").first['a'], 62.5);
  });
}
