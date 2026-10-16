/// Port of Formatting.swift. Swift uses `FormatStyle` (ICU): shortest decimal representation of
/// the double, rounded half-to-even to at most 2 fraction digits, locale grouping and decimal
/// separators. Supported locales: es_AR (default) and en_US (verified against the fixtures).
library;

import 'enums.dart';
import 'load_math.dart';

class GymLocale {
  final String identifier;
  final String decimal;
  final String group;
  const GymLocale._(this.identifier, this.decimal, this.group);

  static const esAR = GymLocale._('es_AR', ',', '.');
  static const enUS = GymLocale._('en_US', '.', ',');

  /// `en_US_POSIX` without grouping (CSV export).
  static const posix = GymLocale._('en_US_POSIX', '.', '');

  static GymLocale of(String identifier) => identifier.startsWith('en') ? enUS : esAR;
}

class GymFormat {
  static const defaultLocale = GymLocale.esAR;

  /// "62,5" in es-AR, "62.5" in en-US. At most `maxFractionDigits` decimals, no trailing zeros.
  static String number(double value, {GymLocale locale = defaultLocale, int maxFractionDigits = 2}) {
    final negative = value < 0 || (value == 0 && value.isNegative);
    final digits = _roundHalfEven(_shortestDecimal(value.abs()), maxFractionDigits);
    var intPart = digits.$1;
    final frac = digits.$2;
    // Grouping by 3 (es-AR and en-US group from 4 digits).
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(locale.group);
      buffer.write(intPart[i]);
    }
    intPart = buffer.toString();
    // ICU keeps the sign of negative values that round to zero (-0.004 → "-0").
    final sign = negative ? '-' : '';
    return frac.isEmpty ? '$sign$intPart' : '$sign$intPart${locale.decimal}$frac';
  }

  /// "62,5 kg"
  static String kg(double value, {GymLocale locale = defaultLocale}) => '${number(value, locale: locale)} kg';

  /// Load as the user thinks about it (see Swift `GymFormat.load`).
  static String load(double value, MeasurementType measurement, LoadMode loadMode, {GymLocale locale = defaultLocale}) {
    switch (measurement) {
      case MeasurementType.weightReps:
      case MeasurementType.duration:
        if (measurement == MeasurementType.duration && LoadMath.key(value) == 0) return 'sin carga';
        final base = kg(value, locale: locale);
        return loadMode == LoadMode.perSide ? '$base por lado' : base;
      case MeasurementType.bodyweightReps:
        final k = LoadMath.key(value);
        if (k == 0) return 'peso corporal';
        if (k > 0) return 'peso corporal +${kg(value, locale: locale)}';
        return 'peso corporal con ${kg(-value, locale: locale)} de asistencia';
    }
  }

  /// "12, 12, 12"
  static String list(List<int> values) => values.join(', ');

  /// Shortest round-trip decimal digits of a non-negative double as (integer, fraction).
  static (String, String) _shortestDecimal(double v) {
    var s = v.toString();
    if (s.contains('e') || s.contains('E')) {
      // Very large/small magnitudes: fall back to a fixed representation.
      s = v.toStringAsFixed(10);
      s = s.contains('.') ? s.replaceFirst(RegExp(r'0+$'), '') : s;
      if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    }
    final parts = s.split('.');
    var frac = parts.length > 1 ? parts[1] : '';
    if (frac == '0') frac = '';
    return (parts[0], frac);
  }

  /// Decimal-string rounding, half to even (ICU default).
  static (String, String) _roundHalfEven((String, String) d, int maxFraction) {
    var (intPart, frac) = d;
    if (frac.length <= maxFraction) return (intPart, frac.replaceFirst(RegExp(r'0+$'), ''));
    final kept = frac.substring(0, maxFraction);
    final rest = frac.substring(maxFraction);
    final first = rest.codeUnitAt(0) - 48;
    final restIsExactlyHalf = first == 5 && rest.substring(1).replaceAll('0', '').isEmpty;
    final lastKept = (intPart + kept).codeUnitAt((intPart + kept).length - 1) - 48;
    final roundUp = first > 5 || (first == 5 && !restIsExactlyHalf) || (restIsExactlyHalf && lastKept.isOdd);
    var digits = intPart + kept;
    if (roundUp) {
      final chars = digits.split('');
      var i = chars.length - 1;
      while (i >= 0) {
        final c = chars[i].codeUnitAt(0) - 48;
        if (c == 9) {
          chars[i] = '0';
          i--;
        } else {
          chars[i] = String.fromCharCode(48 + c + 1);
          break;
        }
      }
      digits = chars.join();
      if (i < 0) digits = '1$digits';
    }
    final newInt = digits.substring(0, digits.length - maxFraction);
    final newFrac = digits.substring(digits.length - maxFraction).replaceFirst(RegExp(r'0+$'), '');
    return (newInt.isEmpty ? '0' : newInt, newFrac);
  }
}
