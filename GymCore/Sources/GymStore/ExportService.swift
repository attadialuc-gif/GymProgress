import Foundation
import GymCore

public struct ImportSummary: Sendable, Hashable {
    public var inserted: Int
    public var updated: Int
    public var unchanged: Int
}

/// Export / import / backup on top of `GymDatabase` (Codable DTO with `schemaVersion`, decoupled
/// from SwiftData). Import validates first and merges by id: re-importing the same file never
/// duplicates anything.
@MainActor
public struct ExportService {
    public let repository: any GymRepository

    public init(repository: any GymRepository) {
        self.repository = repository
    }

    public func exportJSON(now: Date) throws -> Data {
        var db = repository.snapshot()
        db.exportedAt = now
        return try GymJSON.encoder.encode(db)
    }

    /// Decodes and validates without touching the repository.
    public func validate(_ data: Data) throws -> GymDatabase {
        let db: GymDatabase
        do {
            db = try GymJSON.decoder.decode(GymDatabase.self, from: data)
        } catch {
            throw GymStoreError.invalidImport("El archivo no es una copia válida de GymProgress.")
        }
        guard db.schemaVersion >= 1, db.schemaVersion <= GymSchema.currentVersion else {
            throw GymStoreError.unsupportedSchemaVersion(db.schemaVersion)
        }
        let current = repository.snapshot()
        let sessionIds = Set(db.sessions.map(\.id)).union(current.sessions.map(\.id))
        let logIds = Set(db.exerciseLogs.map(\.id)).union(current.exerciseLogs.map(\.id))
        let exerciseIds = Set(db.exercises.map(\.id)).union(current.exercises.map(\.id))
        let routineIds = Set(db.routines.map(\.id)).union(current.routines.map(\.id))

        if let bad = db.exerciseLogs.first(where: { !sessionIds.contains($0.sessionId) }) {
            throw GymStoreError.invalidImport("Registro de ejercicio sin sesión: \(bad.id)")
        }
        if let bad = db.setLogs.first(where: { !logIds.contains($0.exerciseLogId) }) {
            throw GymStoreError.invalidImport("Serie sin ejercicio: \(bad.id)")
        }
        if let bad = db.decisions.first(where: { !logIds.contains($0.exerciseLogId) }) {
            throw GymStoreError.invalidImport("Decisión sin ejercicio: \(bad.id)")
        }
        if let bad = db.routineExercises.first(where: { !routineIds.contains($0.routineId) || !exerciseIds.contains($0.exerciseId) }) {
            throw GymStoreError.invalidImport("Ejercicio de rutina inválido: \(bad.id)")
        }
        for set in db.setLogs {
            if SetValidator.validate(weight: set.weight, reps: set.reps, seconds: set.seconds, rir: set.rir, rpe: set.rpe).contains(where: \.isError) {
                throw GymStoreError.invalidImport("Serie con valores inválidos: \(set.id)")
            }
        }
        return db
    }

    /// Validates, then merges by id (all-or-nothing). Open sessions in the file are imported as-is.
    @discardableResult
    public func importJSON(_ data: Data) throws -> ImportSummary {
        let incoming = try validate(data)
        let before = repository.snapshot()
        let summary = Self.diff(before: before, incoming: incoming)
        try repository.merge(incoming)
        return summary
    }

    /// CSV of every set of completed sessions (one row per set). RFC 4180, comma separator, dot
    /// decimals and ISO-8601 dates so any spreadsheet or script can read it unambiguously.
    public func exportSetsCSV() -> String {
        var rows = ["session_id,session_start,routine,exercise,variant,equipment,set_index,set_kind,status,weight_kg,reps,seconds,added_kg,assistance_kg,rir,rpe,atypical"]
        let iso = ISO8601DateFormatter()
        for session in repository.sessions() where session.status == .completed {
            for log in repository.exerciseLogs(sessionId: session.id) {
                for set in repository.setLogs(exerciseLogId: log.id) {
                    let fields: [String] = [
                        session.id.uuidString,
                        iso.string(from: session.startedAt),
                        session.routineNameSnapshot ?? "",
                        log.snapshot.name,
                        log.variantLabel ?? "",
                        log.equipmentLabel ?? "",
                        String(set.index),
                        set.kind.rawValue,
                        set.status.rawValue,
                        Self.num(set.weight),
                        set.reps.map(String.init) ?? "",
                        set.seconds.map(String.init) ?? "",
                        Self.num(set.addedWeight),
                        Self.num(set.assistance),
                        Self.num(set.rir),
                        Self.num(set.rpe),
                        (session.isAtypical || log.isAtypical) ? "1" : "0",
                    ]
                    rows.append(fields.map(Self.escape).joined(separator: ","))
                }
            }
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func num(_ v: Double?) -> String {
        guard let v else { return "" }
        return v.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }

    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func diff(before: GymDatabase, incoming: GymDatabase) -> ImportSummary {
        var inserted = 0, updated = 0, unchanged = 0
        func count<T: Identifiable & Equatable>(_ old: [T], _ new: [T]) where T.ID: Hashable {
            let existing = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            for item in new {
                if let e = existing[item.id] { if e == item { unchanged += 1 } else { updated += 1 } } else { inserted += 1 }
            }
        }
        count(before.exercises, incoming.exercises)
        count(before.routines, incoming.routines)
        count(before.routineExercises, incoming.routineExercises)
        count(before.schedule, incoming.schedule)
        count(before.sessions, incoming.sessions)
        count(before.exerciseLogs, incoming.exerciseLogs)
        count(before.setLogs, incoming.setLogs)
        count(before.decisions, incoming.decisions)
        count(before.comparabilityLinks, incoming.comparabilityLinks)
        count(before.goals, incoming.goals)
        return ImportSummary(inserted: inserted, updated: updated, unchanged: unchanged)
    }
}
