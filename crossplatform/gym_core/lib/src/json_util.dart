/// JSON helpers shared by every model. The wire format is the Swift `Codable` one used by
/// exports: same key names, dates as seconds since 1970 (UTC, Double), UUIDs as uppercase
/// strings, nil optionals omitted.
library;

typedef Json = Map<String, Object?>;

/// Swift `Date` ⇄ seconds since 1970. Microsecond precision (enough for every stored instant).
DateTime dateFromJson(Object? v) {
  final seconds = (v as num).toDouble();
  return DateTime.fromMicrosecondsSinceEpoch((seconds * 1e6).round(), isUtc: true);
}

double dateToJson(DateTime d) => d.microsecondsSinceEpoch / 1e6;

DateTime? optDate(Object? v) => v == null ? null : dateFromJson(v);

double? optDouble(Object? v) => v == null ? null : (v as num).toDouble();

int? optInt(Object? v) => v == null ? null : toInt(v);

double toDouble(Object? v) => (v as num).toDouble();

/// Like Swift `JSONDecoder` for `Int`: integral numbers only (10 and 10.0), never 10.5.
int toInt(Object? v) {
  if (v is int) return v;
  final d = (v as num).toDouble();
  if (!d.isFinite || d != d.truncateToDouble()) throw FormatException('Not an integer: $v');
  return d.toInt();
}

final RegExp _uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

/// Swift `UUID` decoding: rejects malformed ids, re-encodes uppercase.
String uuidFromJson(Object? v) {
  final s = v as String;
  if (!_uuidPattern.hasMatch(s)) throw FormatException('Invalid UUID: $s');
  return s.toUpperCase();
}

String? optUuid(Object? v) => v == null ? null : uuidFromJson(v);

bool isUuid(String s) => _uuidPattern.hasMatch(s);

List<T> listOf<T>(Object? v, T Function(Object? e) f) => v == null ? <T>[] : (v as List).map(f).toList();

Json asJson(Object? v) => (v as Map).cast<String, Object?>();

/// Adds `value` under `key` only when non-null (Swift `encodeIfPresent`).
void putOpt(Json json, String key, Object? value) {
  if (value != null) json[key] = value;
}

/// Swift `Date.distantFuture` (year 4001; only used for ordering).
final DateTime distantFuture = DateTime.fromMicrosecondsSinceEpoch(64092211200 * 1000000, isUtc: true);
