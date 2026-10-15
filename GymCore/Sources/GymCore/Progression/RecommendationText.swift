import Foundation

/// Spanish (es-AR) explanation texts for the progression engine. Numbers are formatted with the
/// injected locale. Kept separate from the rules so wording can change without touching logic.
struct RecommendationText {
    let locale: Locale
    let measurement: MeasurementType
    let loadMode: LoadMode
    let config: ProgressionConfig

    private var unit: String { measurement == .duration ? "segundos" : "repeticiones" }
    private var top: Int { measurement == .duration ? config.secondsMax : config.repMax }
    private var bottom: Int { measurement == .duration ? config.secondsMin : config.repMin }

    func load(_ value: Double) -> String {
        GymFormat.load(value, measurement: measurement, loadMode: loadMode, locale: locale)
    }

    private var rangeText: String {
        measurement == .duration ? "\(config.secondsMin)–\(config.secondsMax) s" : "\(config.repMin)–\(config.repMax)"
    }

    private var effortPhrase: String {
        if let rir = config.targetRIR {
            return "te quedaron unas \(rir) repeticiones en reserva"
        }
        return "el esfuerzo fue exigente pero controlado"
    }

    // MARK: No history

    var noHistory: String {
        "Todavía no hay datos suficientes para recomendar una carga. Configurá un objetivo inicial (peso y rango) para empezar."
    }

    var noHistoryInContext: String {
        "Todavía no hay datos suficientes en este contexto (otra máquina o variante). El historial anterior se muestra solo como referencia no equivalente."
    }

    func initialTarget(_ weight: Double) -> String {
        "Objetivo inicial configurado por vos: \(load(weight)) × \(rangeText). Todavía no hay sesiones anteriores para comparar."
    }

    // MARK: Rules

    func longBreak(days: Int, weight: Double) -> String {
        "Pasaron \(days) días desde la última sesión comparable. Reevaluá la carga antes de subir: retomá con \(load(weight)) o menos."
    }

    func incompleteSets(done: Int, weight: Double, mixedLoads: Bool) -> String {
        let withLoad = mixedLoads ? "con la misma carga (\(load(weight)))" : "con \(load(weight))"
        return "En la última sesión completaste \(done) de \(config.targetSets) series \(withLoad). Mantené la carga y completá todas las series antes de subir."
    }

    func increaseHigh(next: Double) -> String {
        let effort = config.targetRIR == nil ? "" : " con el esfuerzo objetivo"
        return "Alcanzaste \(top) \(unit) en todas las series\(effort). Subí a \(load(next)) y volvé a \(bottom) \(unit)."
    }

    func increaseConditional(next: Double) -> String {
        "Podrías subir a \(load(next)) si las series se hicieron con buena técnica y cerca del esfuerzo objetivo."
    }

    var increaseConditions: [String] {
        [
            "No se registró el RIR/RPE de todas las series, así que no se puede confirmar el esfuerzo.",
            "Subí solo si la técnica fue buena y \(effortPhrase).",
        ]
    }

    func noHeavierLoad(weight: Double) -> String {
        "Alcanzaste el tope del rango, pero no hay un peso disponible mayor a \(load(weight)). Mantené la carga o actualizá los pesos disponibles."
    }

    var noHeavierLoadNote: String {
        "Agregá pesos disponibles o cambiá el incremento en los criterios de progresión del ejercicio."
    }

    var bodyweightLoadNote: String {
        "Para sumar carga necesitás cinturón o chaleco con lastre; si no, podés seguir sumando repeticiones."
    }

    func needsConfirmation(achieved: Int, required: Int, weight: Double) -> String {
        "Alcanzaste el tope del rango (\(achieved) de \(required) sesiones consecutivas requeridas). Repetí \(load(weight)) para confirmarlo."
    }

    func effortAboveTarget(weight: Double) -> String {
        let rir = config.targetRIR.map { " (RIR \($0))" } ?? ""
        return "Llegaste a \(top) \(unit), pero con menos reserva que la objetivo\(rir): el esfuerzo estuvo por encima del previsto. Mantené \(load(weight)) hasta lograrlo con el esfuerzo objetivo."
    }

    func repeatedBelowMin() -> String {
        "Dos sesiones comparables seguidas con series por debajo de \(bottom) \(unit). Reevaluá descanso, sueño, técnica y carga; bajar el peso es una opción que decidís vos."
    }

    func performanceDroppedSameLoad(lastTotal: Int, previousTotal: Int, weight: Double) -> String {
        "Rendimiento menor que la sesión anterior (\(lastTotal) vs. \(previousTotal) \(unit) con \(load(weight))). Mantené la carga y revisá descanso, sueño y técnica: una sola sesión no justifica cambiarla."
    }

    func performanceDroppedEstimate(weight: Double) -> String {
        "Rendimiento estimado menor que la sesión anterior. Mantené \(load(weight)) y revisá descanso, sueño y técnica: una sola sesión no justifica cambiar la carga."
    }

    func belowMin(weight: Double) -> String {
        "Algunas series quedaron por debajo de \(bottom) \(unit). Mantené \(load(weight)) y apuntá a llegar a \(bottom) en todas."
    }

    func belowTop(weight: Double) -> String {
        if measurement == .duration {
            return "Rango superior no alcanzado. Mantené \(load(weight)) y sumá \(config.secondsIncrement) segundos en las series por debajo de \(top) s."
        }
        return "Rango superior no alcanzado. Mantené \(load(weight)) y sumá 1 repetición en las series por debajo de \(top)."
    }

    var belowTopConditions: [String] {
        ["No se registró el RIR/RPE de todas las series: sumá solo si podés mantener la técnica y \(effortPhrase)."]
    }

    func repsHeldByEffort(weight: Double) -> String {
        let rir = config.targetRIR.map { " (RIR \($0))" } ?? ""
        return "Rango superior no alcanzado y el esfuerzo ya estuvo por encima del objetivo\(rir). Mantené \(load(weight)) y las mismas \(unit) hasta que te resulte más cómodo."
    }

    func durationTopReached(weight: Double) -> String {
        "Alcanzaste \(top) segundos en todas las series con \(load(weight)). Mantené y, si querés progresar, probá una variante más difícil o sumá carga."
    }

    // MARK: Trend notes

    var plateauNote: String {
        "Posible estancamiento: las últimas sesiones comparables no muestran una mejora clara. Revisá descanso, técnica o la estrategia."
    }

    var decliningNote: String {
        "Tendencia en descenso en las últimas sesiones comparables. Revisá el contexto antes de cambiar la carga."
    }
}
