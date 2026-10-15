import Foundation

/// Conditions under which two performances of an exercise can be compared directly.
/// Two logs are comparable only when their contexts are equal (after label normalization) or the
/// user explicitly linked them with a `ComparabilityLink`.
public struct ComparabilityContext: Codable, Sendable, Hashable {
    public var exerciseId: UUID
    /// Variant chosen by the user ("agarre cerrado", "inclinado 30°"...). Optional.
    public var variantLabel: String?
    /// Specific machine / equipment ("Polea gym A", "Smith"...). Optional.
    public var equipmentLabel: String?
    public var loadMode: LoadMode

    public init(exerciseId: UUID, variantLabel: String? = nil, equipmentLabel: String? = nil, loadMode: LoadMode) {
        self.exerciseId = exerciseId
        self.variantLabel = variantLabel
        self.equipmentLabel = equipmentLabel
        self.loadMode = loadMode
    }

    /// Canonical form: labels trimmed, case- and diacritic-insensitive, empty → nil.
    public var normalized: ComparabilityContext {
        ComparabilityContext(
            exerciseId: exerciseId,
            variantLabel: Self.normalize(variantLabel),
            equipmentLabel: Self.normalize(equipmentLabel),
            loadMode: loadMode
        )
    }

    static func normalize(_ label: String?) -> String? {
        guard let label else { return nil }
        let trimmed = label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_AR"))
        let collapsed = trimmed.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// Stable string used for deterministic ordering.
    public var sortKey: String {
        let n = normalized
        return "\(n.exerciseId.uuidString)|\(n.variantLabel ?? "")|\(n.equipmentLabel ?? "")|\(n.loadMode.rawValue)"
    }
}

/// A manual "treat as equivalent" link between two contexts. Only exists if the user creates it.
/// Links are symmetric and transitive (A~B and B~C implies A~C).
public struct ComparabilityLink: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var a: ComparabilityContext
    public var b: ComparabilityContext
    public var createdAt: Date

    public init(id: UUID = UUID(), a: ComparabilityContext, b: ComparabilityContext, createdAt: Date) {
        self.id = id
        self.a = a
        self.b = b
        self.createdAt = createdAt
    }
}

/// Resolves which contexts are equivalent to a given one.
public struct ComparabilityResolver: Sendable {
    private let links: [ComparabilityLink]

    public init(links: [ComparabilityLink]) {
        self.links = links
    }

    /// All contexts equivalent to `context` (including itself), via the transitive closure of links.
    public func equivalenceClass(of context: ComparabilityContext) -> Set<ComparabilityContext> {
        let start = context.normalized
        var visited: Set<ComparabilityContext> = [start]
        var frontier: [ComparabilityContext] = [start]
        let edges = links.map { ($0.a.normalized, $0.b.normalized) }
        while let current = frontier.popLast() {
            for (a, b) in edges {
                if a == current, !visited.contains(b) {
                    visited.insert(b)
                    frontier.append(b)
                } else if b == current, !visited.contains(a) {
                    visited.insert(a)
                    frontier.append(a)
                }
            }
        }
        return visited
    }

    public func areComparable(_ lhs: ComparabilityContext, _ rhs: ComparabilityContext) -> Bool {
        if lhs.normalized == rhs.normalized { return true }
        return equivalenceClass(of: lhs).contains(rhs.normalized)
    }
}
