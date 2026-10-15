import Foundation

/// Parses user-typed numbers. Accepts comma or dot as decimal separator ("62,5" and "62.5"):
/// in es-AR the comma is the decimal separator, so this is a requirement, not a detail.
/// Rejects thousands separators, signs, multiple separators and non-numeric text.
public enum WeightParser {
    public static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 12 else { return nil }
        var separators = 0
        var normalized = ""
        for ch in trimmed {
            if ch.isASCII, ch.isNumber {
                normalized.append(ch)
            } else if ch == "," || ch == "." {
                separators += 1
                normalized.append(".")
            } else {
                return nil
            }
        }
        guard separators <= 1, normalized != ".", let value = Double(normalized), value.isFinite else { return nil }
        // "1.000" is one thousand in es-AR (dot = thousands separator): ambiguous, so it is rejected
        // instead of being silently read as 1.0.
        if let dot = trimmed.firstIndex(of: "."), dot != trimmed.startIndex,
           trimmed[trimmed.index(after: dot)...].count == 3 {
            return nil
        }
        return LoadMath.normalized(value)
    }

    /// Whole numbers (reps, seconds, RIR without decimals).
    public static func parseInt(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 5, trimmed.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(trimmed)
    }
}

public enum ValidationIssue: Equatable, Sendable {
    /// Blocks saving the value.
    case error(String)
    /// Allowed, but the UI asks "¿seguro?" (never blocks).
    case warning(String)

    public var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

/// Section 10 validations: no negatives; unusual values warn but do not block.
public enum SetValidator {
    public static let unusualWeight: Double = 500
    public static let unusualReps = 100
    public static let unusualSeconds = 3_600

    public static func validate(weight: Double?, reps: Int?, seconds: Int?, rir: Double?, rpe: Double?) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if let w = weight {
            if !w.isFinite || w < 0 { issues.append(.error("El peso no puede ser negativo.")) }
            else if w > unusualWeight { issues.append(.warning("El peso parece inusual (más de \(GymFormat.kg(unusualWeight))).")) }
        }
        if let r = reps {
            if r < 0 { issues.append(.error("Las repeticiones no pueden ser negativas.")) }
            else if r > unusualReps { issues.append(.warning("Más de \(unusualReps) repeticiones: revisá el valor.")) }
        }
        if let s = seconds {
            if s < 0 { issues.append(.error("La duración no puede ser negativa.")) }
            else if s > unusualSeconds { issues.append(.warning("Duración inusual: revisá el valor.")) }
        }
        if let rir, !(0...10).contains(rir) { issues.append(.error("El RIR va de 0 a 10.")) }
        if let rpe, !(1...10).contains(rpe) { issues.append(.error("El RPE va de 1 a 10.")) }
        return issues
    }
}
