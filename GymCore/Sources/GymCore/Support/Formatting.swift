import Foundation

/// Locale-aware formatting helpers (never hand-built decimal strings). Default locale: es-AR.
public enum GymFormat {
    public static let defaultLocale = Locale(identifier: "es_AR")

    /// "62,5" in es-AR, "62.5" in en-US. At most `maxFractionDigits` decimals, no trailing zeros.
    public static func number(_ value: Double, locale: Locale = defaultLocale, maxFractionDigits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxFractionDigits)).locale(locale))
    }

    /// "62,5 kg"
    public static func kg(_ value: Double, locale: Locale = defaultLocale) -> String {
        "\(number(value, locale: locale)) kg"
    }

    /// Describes a load as the user thinks about it, by measurement and load mode.
    /// - weightReps: "62,5 kg" (perSide: "20 kg por lado")
    /// - bodyweightReps: "peso corporal", "peso corporal +10 kg", "peso corporal con 15 kg de asistencia"
    public static func load(_ value: Double, measurement: MeasurementType, loadMode: LoadMode, locale: Locale = defaultLocale) -> String {
        switch measurement {
        case .weightReps, .duration:
            if measurement == .duration, LoadMath.key(value) == 0 { return "sin carga" }
            let base = kg(value, locale: locale)
            return loadMode == .perSide ? "\(base) por lado" : base
        case .bodyweightReps:
            let k = LoadMath.key(value)
            if k == 0 { return "peso corporal" }
            if k > 0 { return "peso corporal +\(kg(value, locale: locale))" }
            return "peso corporal con \(kg(-value, locale: locale)) de asistencia"
        }
    }

    /// "12, 12, 12"
    public static func list(_ values: [Int]) -> String {
        values.map(String.init).joined(separator: ", ")
    }
}
