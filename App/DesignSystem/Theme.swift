import GymCore
import GymStore
import SwiftUI

/// Single accent color for progress, records and primary actions. Dark by default.
enum Theme {
    static let accent = Color("AccentColor")
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let elevatedBackground = Color(uiColor: .tertiarySystemBackground)
    static let positive = Color.green
    static let caution = Color.orange
    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 12

    static func colorScheme(for theme: AppTheme) -> ColorScheme? {
        switch theme {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Rounded container used across the app.
struct Card<Content: View>: View {
    var highlighted = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.7), lineWidth: 1.5)
            }
        }
    }
}

/// Large numbers for weights and reps (scales with Dynamic Type).
struct BigNumber: View {
    let text: String
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(text)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct Badge: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

/// Presentation of loads in the user's unit. Data is always stored in kg (section 5).
struct LoadFormatter {
    var unit: WeightUnit = .kg
    var locale: Locale = GymFormat.defaultLocale

    static let kgPerLb = 0.45359237

    func value(_ kg: Double) -> Double {
        unit == .kg ? kg : kg / Self.kgPerLb
    }

    func weight(_ kg: Double?) -> String {
        guard let kg else { return "—" }
        return "\(GymFormat.number(value(kg), locale: locale)) \(unit.rawValue)"
    }

    /// Load as the engine describes it (body weight, assistance, per side…), converted to the unit.
    func load(_ kg: Double?, measurement: MeasurementType, loadMode: LoadMode) -> String {
        guard let kg else { return "—" }
        if unit == .kg { return GymFormat.load(kg, measurement: measurement, loadMode: loadMode, locale: locale) }
        let converted = GymFormat.load(value(kg), measurement: measurement, loadMode: loadMode, locale: locale)
        return converted.replacingOccurrences(of: " kg", with: " lb")
    }

    /// Parses a typed value in the user's unit (comma or dot) and returns kg.
    func parse(_ text: String) -> Double? {
        guard let v = WeightParser.parse(text) else { return nil }
        return unit == .kg ? v : LoadMath.normalized(v * Self.kgPerLb)
    }

    func editable(_ kg: Double?) -> String {
        guard let kg else { return "" }
        return GymFormat.number(value(kg), locale: locale)
    }
}

extension Recommendation {
    /// Short Spanish title for the card.
    var actionTitle: String {
        switch action {
        case .needsInitialTarget: targetWeight == nil ? "Datos insuficientes" : "Objetivo inicial"
        case .increaseWeight: confidence == .conditional ? "Podrías subir la carga" : "Subí la carga"
        case .increaseReps: "Sumá repeticiones"
        case .maintain: "Mantené la carga"
        case .reassess: "Reevaluá"
        }
    }

    var actionSymbol: String {
        switch action {
        case .needsInitialTarget: "questionmark.circle"
        case .increaseWeight: "arrow.up.circle.fill"
        case .increaseReps: "plus.circle.fill"
        case .maintain: "equal.circle.fill"
        case .reassess: "exclamationmark.triangle.fill"
        }
    }

    var amountsText: String {
        if let seconds = targetSeconds, !seconds.isEmpty { return seconds.map { "\($0) s" }.joined(separator: ", ") }
        return targetReps.isEmpty ? "—" : GymFormat.list(targetReps)
    }
}

extension TrendClassification {
    var label: String {
        switch self {
        case .insufficientData: "Sin datos suficientes (mín. 3 sesiones)"
        case .progressing: "Progresando"
        case .stable: "Estable"
        case .possiblePlateau: "Posible estancamiento"
        case .declining: "En descenso"
        }
    }
}

extension MuscleGroup {
    var label: String {
        switch self {
        case .chest: "Pecho"
        case .upperBack: "Espalda alta"
        case .lats: "Dorsales"
        case .traps: "Trapecios"
        case .frontDelts: "Deltoides anterior"
        case .sideDelts: "Deltoides lateral"
        case .rearDelts: "Deltoides posterior"
        case .biceps: "Bíceps"
        case .triceps: "Tríceps"
        case .forearms: "Antebrazos"
        case .quads: "Cuádriceps"
        case .hamstrings: "Isquiotibiales"
        case .glutes: "Glúteos"
        case .calves: "Gemelos"
        case .adductors: "Aductores"
        case .abductors: "Abductores"
        case .abs: "Abdominales"
        case .obliques: "Oblicuos"
        case .lowerBack: "Zona lumbar"
        }
    }
}

extension Equipment {
    var label: String {
        switch self {
        case .barbell: "Barra"
        case .dumbbell: "Mancuernas"
        case .machine: "Máquina"
        case .cable: "Polea"
        case .smithMachine: "Smith"
        case .kettlebell: "Kettlebell"
        case .bodyweight: "Peso corporal"
        case .band: "Banda"
        case .ezBar: "Barra Z"
        case .other: "Otro"
        }
    }
}

extension MeasurementType {
    var label: String {
        switch self {
        case .weightReps: "Peso × repeticiones"
        case .bodyweightReps: "Peso corporal × repeticiones"
        case .duration: "Duración"
        }
    }
}
