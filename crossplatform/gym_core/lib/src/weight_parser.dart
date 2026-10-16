/// Port of WeightParser.swift: comma or dot as decimal separator, no signs, no thousands
/// separators, no exponents; "1.000" (dot + exactly 3 digits) is rejected as ambiguous in es-AR.
library;

import 'formatting.dart';
import 'load_math.dart';
import 'text.dart';

class WeightParser {
  static bool _isAsciiDigit(int c) => c >= 48 && c <= 57;

  static double? parse(String text) {
    final trimmed = swiftTrim(text);
    if (trimmed.isEmpty || trimmed.runes.length > 12) return null;
    var separators = 0;
    final normalized = StringBuffer();
    for (final c in trimmed.runes) {
      if (_isAsciiDigit(c)) {
        normalized.writeCharCode(c);
      } else if (c == 0x2C || c == 0x2E) {
        separators++;
        normalized.write('.');
      } else {
        return null;
      }
    }
    var s = normalized.toString();
    if (separators > 1 || s == '.') return null;
    if (s.startsWith('.')) s = '0$s';
    if (s.endsWith('.')) s = '${s}0';
    final value = double.tryParse(s);
    if (value == null || !value.isFinite) return null;
    final dot = trimmed.indexOf('.');
    if (dot > 0 && trimmed.substring(dot + 1).runes.length == 3) return null;
    return LoadMath.normalized(value);
  }

  /// Whole numbers (reps, seconds, RIR without decimals), at most 5 digits.
  static int? parseInt(String text) {
    final trimmed = swiftTrim(text);
    if (trimmed.isEmpty || trimmed.runes.length > 5 || !trimmed.runes.every(_isAsciiDigit)) return null;
    return int.parse(trimmed);
  }
}

class ValidationIssue {
  final bool isError;
  final String message;
  const ValidationIssue.error(this.message) : isError = true;
  const ValidationIssue.warning(this.message) : isError = false;

  @override
  bool operator ==(Object other) => other is ValidationIssue && other.isError == isError && other.message == message;

  @override
  int get hashCode => Object.hash(isError, message);
}

/// Section 10 validations: no negatives; unusual values warn but do not block.
class SetValidator {
  static const double unusualWeight = 500;
  static const int unusualReps = 100;
  static const int unusualSeconds = 3600;

  static List<ValidationIssue> validate({double? weight, int? reps, int? seconds, double? rir, double? rpe}) {
    final issues = <ValidationIssue>[];
    if (weight != null) {
      if (!weight.isFinite || weight < 0) {
        issues.add(const ValidationIssue.error('El peso no puede ser negativo.'));
      } else if (weight > unusualWeight) {
        issues.add(ValidationIssue.warning('El peso parece inusual (más de ${GymFormat.kg(unusualWeight)}).'));
      }
    }
    if (reps != null) {
      if (reps < 0) {
        issues.add(const ValidationIssue.error('Las repeticiones no pueden ser negativas.'));
      } else if (reps > unusualReps) {
        issues.add(const ValidationIssue.warning('Más de $unusualReps repeticiones: revisá el valor.'));
      }
    }
    if (seconds != null) {
      if (seconds < 0) {
        issues.add(const ValidationIssue.error('La duración no puede ser negativa.'));
      } else if (seconds > unusualSeconds) {
        issues.add(const ValidationIssue.warning('Duración inusual: revisá el valor.'));
      }
    }
    if (rir != null && !(rir >= 0 && rir <= 10)) issues.add(const ValidationIssue.error('El RIR va de 0 a 10.'));
    if (rpe != null && !(rpe >= 1 && rpe <= 10)) issues.add(const ValidationIssue.error('El RPE va de 1 a 10.'));
    return issues;
  }
}
