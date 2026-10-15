import Foundation

/// How a volume figure was obtained. The UI must show it next to the number.
public enum VolumeBasis: String, Codable, Sendable, Hashable {
    /// External load × reps.
    case external
    /// Body-weight work with known body weight: (body weight + added − assistance) × reps.
    case bodyweightIncluded
    /// Body-weight work without known body weight: only the added load is counted.
    case externalOnlyBodyweightUnknown
    /// Duration exercises have no load volume (see `timeUnderLoadSeconds`).
    case notApplicable
}

/// Load volume of one performance (section 8.1). "Volume" never implies strength or hypertrophy.
public struct LoadVolume: Codable, Sendable, Hashable {
    /// Total kg moved. For `perSide` = 2 × `perSide` (both sides do the same work).
    public var total: Double
    /// Per-side figure, only for `perSide` load mode.
    public var perSide: Double?
    public var basis: VolumeBasis
    public var effectiveSets: Int
    /// Reps of effective sets (unilateral reps are counted per side, as recorded).
    public var reps: Int
    public var timeUnderLoadSeconds: Int

    public static let zero = LoadVolume(total: 0, perSide: nil, basis: .external, effectiveSets: 0, reps: 0, timeUnderLoadSeconds: 0)
}

public enum Volume {
    /// Volume of the effective sets of a performance (warm-ups and pending sets excluded).
    public static func of(_ performance: ExercisePerformance, bodyweight: Double? = nil) -> LoadVolume {
        let sets = performance.effectiveSets
        let reps = sets.reduce(0) { $0 + ($1.reps ?? 0) }
        let seconds = sets.reduce(0) { $0 + ($1.seconds ?? 0) }

        switch performance.measurement {
        case .weightReps:
            let raw = sets.reduce(0.0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
            let value = LoadMath.normalized(raw)
            if performance.context.loadMode == .perSide {
                return LoadVolume(total: LoadMath.normalized(value * 2), perSide: value, basis: .external, effectiveSets: sets.count, reps: reps, timeUnderLoadSeconds: seconds)
            }
            return LoadVolume(total: value, perSide: nil, basis: .external, effectiveSets: sets.count, reps: reps, timeUnderLoadSeconds: seconds)

        case .bodyweightReps:
            if let bw = bodyweight, bw.isFinite, bw > 0 {
                let raw = sets.reduce(0.0) { acc, s in acc + max(0, bw + s.netAddedLoad) * Double(s.reps ?? 0) }
                return LoadVolume(total: LoadMath.normalized(raw), perSide: nil, basis: .bodyweightIncluded, effectiveSets: sets.count, reps: reps, timeUnderLoadSeconds: seconds)
            }
            let raw = sets.reduce(0.0) { $0 + ($1.addedWeight ?? 0) * Double($1.reps ?? 0) }
            return LoadVolume(total: LoadMath.normalized(raw), perSide: nil, basis: .externalOnlyBodyweightUnknown, effectiveSets: sets.count, reps: reps, timeUnderLoadSeconds: seconds)

        case .duration:
            return LoadVolume(total: 0, perSide: nil, basis: .notApplicable, effectiveSets: sets.count, reps: reps, timeUnderLoadSeconds: seconds)
        }
    }
}

/// Input for muscle-group volume: a performance plus the muscles frozen in its log snapshot.
public struct MuscleWork: Sendable, Hashable {
    public var performance: ExercisePerformance
    public var primary: [MuscleGroup]
    public var secondary: [MuscleInvolvement]

    public init(performance: ExercisePerformance, primary: [MuscleGroup], secondary: [MuscleInvolvement]) {
        self.performance = performance
        self.primary = primary
        self.secondary = secondary
    }
}

/// Weekly sets per muscle. Direct and indirect sets are always reported separately.
public struct MuscleSetVolume: Codable, Sendable, Hashable {
    public var muscle: MuscleGroup
    /// Effective sets of exercises where the muscle is primary.
    public var directSets: Int
    /// Effective sets where the muscle is secondary × participation factor (estimate).
    public var indirectSets: Double
    /// Distinct training days with at least one direct set.
    public var frequencyDays: Int
}

public enum MuscleVolume {
    /// - Parameters:
    ///   - indirectFactor: global factor for secondary muscles without their own factor (default 0.5).
    ///   - calendar: used to count distinct training days.
    public static func compute(_ work: [MuscleWork], indirectFactor: Double = 0.5, calendar: Calendar) -> [MuscleSetVolume] {
        var direct: [MuscleGroup: Int] = [:]
        var indirect: [MuscleGroup: Double] = [:]
        var days: [MuscleGroup: Set<Date>] = [:]

        for item in work {
            let count = item.performance.effectiveSets.count
            guard count > 0 else { continue }
            let day = calendar.startOfDay(for: item.performance.sessionStart)
            let primary = Set(item.primary)
            for muscle in primary {
                direct[muscle, default: 0] += count
                days[muscle, default: []].insert(day)
            }
            for involvement in item.secondary where !primary.contains(involvement.muscle) {
                let factor = min(max(involvement.factor ?? indirectFactor, 0), 1)
                indirect[involvement.muscle, default: 0] += Double(count) * factor
            }
        }

        let muscles = Set(direct.keys).union(indirect.keys)
        return muscles.sorted().map { muscle in
            MuscleSetVolume(
                muscle: muscle,
                directSets: direct[muscle] ?? 0,
                indirectSets: (indirect[muscle] ?? 0).rounded(toPlaces: 3),
                frequencyDays: days[muscle]?.count ?? 0
            )
        }
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}
