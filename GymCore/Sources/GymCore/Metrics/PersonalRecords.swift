import Foundation

public enum RecordKind: String, Codable, Sendable, Hashable {
    /// Heaviest load lifted in an effective set (real).
    case maxWeight
    /// Most reps at a given load (real).
    case maxRepsAtWeight
    /// Best estimated 1RM (calculated, `isEstimated == true`).
    case bestEstimatedOneRepMax
    /// Highest load volume in one session (real).
    case maxSessionVolume
}

/// A record derived from history. Always recomputable from the sets; never invented.
public struct PersonalRecord: Codable, Sendable, Hashable {
    public var kind: RecordKind
    public var value: Double
    /// Load for `maxRepsAtWeight` (the value is the reps).
    public var weight: Double?
    public var reps: Int?
    public var date: Date
    public var sessionId: UUID
    public var exerciseLogId: UUID
    public var setIndex: Int?
    public var isEstimated: Bool
}

public struct RecordSummary: Codable, Sendable, Hashable {
    public var maxWeight: PersonalRecord?
    public var bestEstimatedOneRepMax: PersonalRecord?
    public var maxSessionVolume: PersonalRecord?
    /// Best reps per load, sorted by load.
    public var maxRepsAtWeight: [PersonalRecord]
    /// Every time a record improved, chronologically (first occurrence wins ties).
    public var history: [PersonalRecord]

    public static let empty = RecordSummary(maxWeight: nil, bestEstimatedOneRepMax: nil, maxSessionVolume: nil, maxRepsAtWeight: [], history: [])
}

public enum PersonalRecords {
    /// Records from completed sessions only. Pass performances of one comparability class
    /// (different machines are not comparable). Atypical sessions still count: a real lift is real.
    public static func compute(_ performances: [ExercisePerformance], oneRepMax: OneRepMaxSettings = .default, bodyweight: Double? = nil) -> RecordSummary {
        let ordered = performances
            .filter { $0.sessionStatus == .completed && $0.measurement == .weightReps }
            .sorted { a, b in
                if a.sessionStart != b.sessionStart { return a.sessionStart < b.sessionStart }
                return a.exerciseLogId.uuidString < b.exerciseLogId.uuidString
            }

        var summary = RecordSummary.empty
        var repsAtWeight: [Int: PersonalRecord] = [:]

        for perf in ordered {
            for set in perf.effectiveSets {
                guard let w = set.weight, let r = set.reps else { continue }
                let weight = LoadMath.normalized(w)

                if weight > 0, summary.maxWeight.map({ LoadMath.key(weight) > LoadMath.key($0.value) }) ?? true {
                    let record = PersonalRecord(kind: .maxWeight, value: weight, weight: weight, reps: r, date: perf.sessionStart, sessionId: perf.sessionId, exerciseLogId: perf.exerciseLogId, setIndex: set.index, isEstimated: false)
                    summary.maxWeight = record
                    summary.history.append(record)
                }

                let key = LoadMath.key(weight)
                if weight > 0, repsAtWeight[key].map({ r > ($0.reps ?? 0) }) ?? true {
                    let record = PersonalRecord(kind: .maxRepsAtWeight, value: Double(r), weight: weight, reps: r, date: perf.sessionStart, sessionId: perf.sessionId, exerciseLogId: perf.exerciseLogId, setIndex: set.index, isEstimated: false)
                    repsAtWeight[key] = record
                }

                if !set.excludedFromEstimates, let e1rm = OneRepMax.estimate(weight: weight, reps: r, settings: oneRepMax) {
                    let value = LoadMath.normalized(e1rm)
                    if summary.bestEstimatedOneRepMax.map({ LoadMath.key(value) > LoadMath.key($0.value) }) ?? true {
                        let record = PersonalRecord(kind: .bestEstimatedOneRepMax, value: value, weight: weight, reps: r, date: perf.sessionStart, sessionId: perf.sessionId, exerciseLogId: perf.exerciseLogId, setIndex: set.index, isEstimated: true)
                        summary.bestEstimatedOneRepMax = record
                        summary.history.append(record)
                    }
                }
            }

            let volume = Volume.of(perf, bodyweight: bodyweight).total
            if volume > 0, summary.maxSessionVolume.map({ LoadMath.key(volume) > LoadMath.key($0.value) }) ?? true {
                let record = PersonalRecord(kind: .maxSessionVolume, value: volume, weight: nil, reps: nil, date: perf.sessionStart, sessionId: perf.sessionId, exerciseLogId: perf.exerciseLogId, setIndex: nil, isEstimated: false)
                summary.maxSessionVolume = record
                summary.history.append(record)
            }
        }

        summary.maxRepsAtWeight = repsAtWeight.values.sorted { ($0.weight ?? 0) < ($1.weight ?? 0) }
        return summary
    }
}
