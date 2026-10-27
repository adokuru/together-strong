import Foundation

enum Profile: String, Codable, CaseIterable {
    case david = "David"
    case mary = "Mary"
}

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var string: String? { if case .string(let value) = self { value } else { nil } }
}

// Preserve the complete server document, including fields this milestone does not edit.
struct WorkoutDocument: Codable, Equatable {
    private var fields: [String: JSONValue]

    init(from decoder: any Decoder) throws {
        let fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
        guard fields["version"] == .number(1),
              fields["rampSets"] == .number(1) || fields["rampSets"] == .number(2),
              let sessions = fields["sessions"]?.array, sessions.count <= 1_000 else {
            throw APIError.invalidDocument
        }
        self.fields = fields
        var ids = Set<String>(), days = Set<String>()
        for value in sessions {
            let session = try WorkoutSession(value: value)
            guard ids.insert(session.id).inserted,
                  session.discarded || days.insert(session.date).inserted else { throw APIError.invalidDocument }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }

    var rampSets: Int {
        get { fields["rampSets"] == .number(1) ? 1 : 2 }
        set { fields["rampSets"] = .number(Double(newValue)) }
    }
    var sessionCount: Int { fields["sessions"]?.array?.count ?? 0 }
    var completedSessionCount: Int { sessions.filter { !$0.discarded && $0.isCompleted }.count }
}

struct WorkoutEnvelope: Codable, Equatable {
    var data: WorkoutDocument
    var revision: Int
}

struct Account: Codable, Equatable {
    let userId: String
    let profile: Profile
    let needsPassword: Bool
}

struct SyncRecord: Codable, Equatable {
    var base: WorkoutEnvelope
    var local: WorkoutDocument
    var sent: WorkoutDocument?
    var recoveryCopy: WorkoutDocument?
    var restTimer: RestTimerState?
    var restAlertsEnabled: Bool?
    var isDirty: Bool { local != base.data }
}

extension WorkoutDocument {
    var sessions: [WorkoutSession] {
        get { (fields["sessions"]?.array ?? []).map(WorkoutSession.init(validatedValue:)) }
        set { fields["sessions"] = .array(newValue.map(\.value)) }
    }
    var startedAt: String? { fields["startedAt"]?.string }
    var activeSessionID: String? { fields["activeSessionId"]?.string }

    func weekNumber(now: Date = Date()) -> Int {
        guard sessions.contains(where: { $0.doneCount > 0 }), let startedAt,
              let first = WorkoutDate.parse(startedAt) else { return 1 }
        return max(1, Int(floor(now.timeIntervalSince(first) / 604800)) + 1)
    }

    func activeSession(now: Date = Date(), calendar: Calendar = WorkoutDate.calendar) -> WorkoutSession? {
        let available = sessions.filter { !$0.discarded }
        let today = WorkoutDate.day(now, calendar: calendar)
        return available.first { $0.id == activeSessionID && (!$0.isCompleted || $0.day(calendar: calendar) == today) }
            ?? available.last { !$0.isCompleted }
            ?? available.first { $0.date == today }
    }

    func session(_ id: String) -> WorkoutSession? { sessions.first { $0.id == id } }

    mutating func updateSession(_ session: WorkoutSession) {
        sessions = sessions.map { $0.id == session.id ? session : $0 }
    }

    @discardableResult
    mutating func start(profile: Profile, warmup: WarmupState? = nil, now: Date = Date(), calendar: Calendar = WorkoutDate.calendar) throws -> String {
        var session: WorkoutSession
        if let existing = activeSession(now: now, calendar: calendar) {
            if existing.isCompleted { return existing.id }
            session = existing
        } else {
            guard sessions.count < 1000 else { throw WorkoutError.historyLimit }
            session = WorkoutSession(profile: profile, rampSets: rampSets, week: weekNumber(now: now), now: now, calendar: calendar)
            sessions.append(session)
        }
        session.set("completedAt", nil); session.set("pausedAt", nil)
        session.set("status", .string("active"))
        if let warmup { session.setWarmup(warmup) }
        updateSession(session)
        fields["activeSessionId"] = .string(session.id)
        return session.id
    }

    mutating func select(_ id: String) throws {
        guard let session = session(id), !session.discarded else { throw WorkoutError.unavailable }
        fields["activeSessionId"] = .string(id)
    }

    mutating func setWarmup(_ id: String, state: WarmupState) throws {
        guard var session = session(id), !session.discarded, !session.isCompleted else { throw WorkoutError.readOnly }
        session.setWarmup(state); updateSession(session)
    }

    mutating func editSet(_ id: String, exercise: String, index: Int, reps: String? = nil, kg: String? = nil, toggle: Bool = false, now: Date = Date()) throws {
        guard var session = session(id), !session.discarded, !session.isCompleted,
              let definition = Exercise.all.first(where: { $0.id == exercise }) else { throw WorkoutError.readOnly }
        var sets = session.sets(exercise)
        guard sets.indices.contains(index) else { throw WorkoutError.unavailable }
        var set = sets[index]
        if let reps { guard reps.utf16.count <= 3 else { throw WorkoutError.input("Use at most 3 digits for reps.") }; set.reps = reps; set.done = false }
        if let kg { guard kg.utf16.count <= 6 else { throw WorkoutError.input("Use at most 6 characters for total kg.") }; set.kg = kg; set.done = false }
        if toggle {
            guard set.done || set.valid(bodyweight: definition.bodyweight) else {
                throw WorkoutError.input(definition.bodyweight ? "Enter 1 to 100 reps per side before completing this set." : "Enter 1 to 100 reps and total kg from 0 to 200, with at most 2 decimal places.")
            }
            set.done.toggle()
            if set.done {
                if !sessions.contains(where: { $0.doneCount > 0 }) { fields["startedAt"] = .string(WorkoutDate.timestamp(now)) }
                if session.trainingStartedAt == nil { session.set("trainingStartedAt", .string(WorkoutDate.timestamp(now))) }
            }
        }
        sets[index] = set; session.replaceSets(exercise, sets)
        session.set("completedAt", nil); session.set("status", .string("active"))
        session.set("pausedAt", nil); updateSession(session)
    }

    mutating func pause(_ id: String, now: Date = Date()) throws {
        guard var session = session(id), !session.discarded, !session.isCompleted else { throw WorkoutError.readOnly }
        session.set("status", .string(session.doneCount == 0 ? "draft" : "paused"))
        session.set("pausedAt", .string(WorkoutDate.timestamp(now))); updateSession(session)
    }

    mutating func finish(_ id: String, now: Date = Date()) throws {
        guard var session = session(id), !session.discarded else { throw WorkoutError.unavailable }
        if session.isCompleted { return }
        guard session.doneCount > 0 else { throw WorkoutError.emptySession }
        session.set("completedAt", .string(WorkoutDate.timestamp(now))); updateSession(session)
    }

    mutating func reopen(_ id: String, now: Date = Date(), calendar: Calendar = WorkoutDate.calendar) throws {
        guard var session = session(id), session.isCompleted,
              session.day(calendar: calendar) == WorkoutDate.day(now, calendar: calendar) else { throw WorkoutError.readOnly }
        session.set("completedAt", nil); session.set("status", .string("active"))
        updateSession(session); fields["activeSessionId"] = .string(id)
    }

    mutating func discard(_ id: String, now: Date = Date()) throws {
        guard var session = session(id), session.doneCount == 0 else { throw WorkoutError.readOnly }
        session.set("discardedAt", .string(WorkoutDate.timestamp(now))); updateSession(session)
    }

    mutating func restoreDraft(_ id: String) throws {
        guard var session = session(id), session.discarded else { throw WorkoutError.unavailable }
        guard !sessions.contains(where: { $0.id != id && !$0.discarded && $0.date == session.date }) else { throw WorkoutError.duplicateDay }
        session.set("discardedAt", nil); updateSession(session); fields["activeSessionId"] = .string(id)
    }
}
