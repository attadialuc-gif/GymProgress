import GymCore
import GymStore
import SwiftUI

/// Set table: number · load · reps (or seconds) · RIR · type · state, with last session's value
/// next to each set. Every edit is saved immediately.
struct SetTable: View {
    @Environment(AppModel.self) private var model
    let log: ExerciseLog
    let sets: [SetLog]
    let previous: PerformanceSummary?
    let onComplete: (SetLog) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Serie").frame(width: 44, alignment: .leading)
                Text(loadHeader).frame(maxWidth: .infinity, alignment: .leading)
                Text(log.snapshot.measurement == .duration ? "Seg." : "Reps").frame(width: 64)
                Text("RIR").frame(width: 52)
                Spacer().frame(width: 44)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            ForEach(Array(sets.enumerated()), id: \.element.id) { position, set in
                SetRow(
                    log: log,
                    entry: set,
                    label: label(for: set, position: position),
                    previous: previousText(for: set),
                    onComplete: { onComplete(set) }
                )
            }
        }
    }

    private var loadHeader: String {
        let unit = model.settings.weightUnit.rawValue
        switch log.snapshot.measurement {
        case .bodyweightReps: return "Lastre (+) / asist. (−) \(unit)"
        case .weightReps, .duration: return log.snapshot.loadMode == .perSide ? "Peso por lado (\(unit))" : "Peso (\(unit))"
        }
    }

    private func label(for set: SetLog, position: Int) -> String {
        if set.kind == .warmup { return "C" }
        let workingIndex = sets.filter { $0.kind != .warmup }.firstIndex { $0.id == set.id } ?? position
        return "\(workingIndex + 1)"
    }

    private func previousText(for set: SetLog) -> String? {
        guard set.kind == .working, let previous else { return nil }
        let working = sets.filter { $0.kind == .working }
        guard let i = working.firstIndex(where: { $0.id == set.id }), i < previous.sets.count else { return nil }
        let p = previous.sets[i]
        return "Antes: \(model.loadFormatter.editable(p.load)) × \(p.amount)"
    }
}
