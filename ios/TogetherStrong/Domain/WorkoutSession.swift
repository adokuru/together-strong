import Foundation

enum WarmupState: String { case pending, underway, done, skipped }

enum WorkoutError: Error, LocalizedError {
    case unavailable, readOnly, emptySession, historyLimit, duplicateDay, input(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "This session is unavailable. Refresh your workouts and retry."
        case .readOnly: "Reopen this completed workout before making changes."
        case .emptySession: "Complete at least one set before finishing. Empty sessions stay drafts."
        case .historyLimit: "Your history has reached this version's limit. Your saved sessions are preserved."
        case .duplicateDay: "Another session already uses that date. Your discarded draft is still preserved."
        case .input(let text): text
        }
    }
}

enum WorkoutDate {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
    static func day(_ date: Date, calendar: Calendar = WorkoutDate.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

struct SetEntry: Equatable {
    var fields: [String: JSONValue]
    var reps: String { get { fields["reps"]?.string ?? "" } set { fields["reps"] = .string(newValue) } }
    var kg: String { get { fields["kg"]?.string ?? "" } set { fields["kg"] = .string(newValue) } }
    var done: Bool { get { fields["done"] == .bool(true) } set { fields["done"] = .bool(newValue) } }

    func valid(bodyweight: Bool) -> Bool {
        guard reps.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              let count = Int(reps), (1...100).contains(count) else { return false }
        if bodyweight { return true }
        return kg.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil && (Double(kg) ?? .infinity) <= 200
    }
    static var empty: SetEntry { SetEntry(fields: ["reps": .string(""), "kg": .string(""), "done": .bool(false)]) }
}

struct WorkoutSession: Equatable {
    private var fields: [String: JSONValue]
    var value: JSONValue { .object(fields) }
    var id: String { fields["id"]?.string ?? "" }
    var date: String { fields["date"]?.string ?? "" }
    var completedAt: String? { fields["completedAt"]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    var trainingStartedAt: String? { fields["trainingStartedAt"]?.string }
    var discarded: Bool { !(fields["discardedAt"]?.string ?? "").isEmpty }
    var isPaused: Bool { !(fields["pausedAt"]?.string ?? "").isEmpty }
    var warmup: WarmupState { WarmupState(rawValue: fields["warmupState"]?.string ?? "") ?? (fields["warmup"] == .bool(true) ? .done : .pending) }
    var doneCount: Int { (fields["sets"]?.object ?? [:]).values.flatMap { $0.array ?? [] }.filter { $0.object?["done"] == .bool(true) }.count }
    var totalCount: Int { (fields["sets"]?.object ?? [:]).values.reduce(0) { $0 + ($1.array?.count ?? 0) } }
    var isCompleted: Bool { completedAt != nil && doneCount > 0 }
    var stage: String { isCompleted ? "complete" : doneCount == 0 ? "draft" : fields["status"] == .string("paused") ? "paused" : "active" }

    init(validatedValue value: JSONValue) {
        guard let fields = value.object else { preconditionFailure("WorkoutDocument only contains validated session objects") }
        self.fields = fields
    }

    init(value: JSONValue) throws {
        guard let fields = value.object, let id = fields["id"]?.string, id.utf16.count <= 80,
              let date = fields["date"]?.string, date.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil,
              let started = fields["startedAt"]?.string, WorkoutDate.parse(started) != nil,
              case .bool = fields["warmup"], let sets = fields["sets"]?.object else { throw APIError.invalidDocument }
        self.fields = fields
        for (id, value) in sets {
            guard let exercise = Exercise.all.first(where: { $0.id == id }),
                  let entries = value.array, (1...3).contains(entries.count) else { throw APIError.invalidDocument }
            for value in entries {
                guard let entry = value.object, let reps = entry["reps"]?.string, reps.utf16.count <= 3,
                      let kg = entry["kg"]?.string, kg.utf16.count <= 6, case .bool = entry["done"] else { throw APIError.invalidDocument }
                let set = SetEntry(fields: entry)
                guard !set.done || set.valid(bodyweight: exercise.bodyweight) else { throw APIError.invalidDocument }
            }
        }
        if discarded && doneCount > 0 { throw APIError.invalidDocument }
    }

    init(profile: Profile, rampSets: Int, week: Int, now: Date, calendar: Calendar) {
        fields = ["id": .string(UUID().uuidString.lowercased()), "date": .string(WorkoutDate.day(now, calendar: calendar)),
                  "startedAt": .string(WorkoutDate.timestamp(now)), "warmup": .bool(false),
                  "warmupState": .string("pending"), "status": .string("draft"), "sets": .object([:])]
        for exercise in Exercise.routine(profile) {
            replaceSets(exercise.id, Array(repeating: .empty, count: week <= 2 ? rampSets : exercise.sets))
        }
    }

    mutating func set(_ key: String, _ value: JSONValue?) { fields[key] = value }
    mutating func setWarmup(_ state: WarmupState) { fields["warmupState"] = .string(state.rawValue); fields["warmup"] = .bool(state == .done) }
    func sets(_ exercise: String) -> [SetEntry] { (fields["sets"]?.object?[exercise]?.array ?? []).compactMap { $0.object.map(SetEntry.init(fields:)) } }
    mutating func replaceSets(_ exercise: String, _ sets: [SetEntry]) {
        var current = fields["sets"]?.object ?? [:]
        current[exercise] = .array(sets.map { .object($0.fields) }); fields["sets"] = .object(current)
    }
    func day(calendar: Calendar = WorkoutDate.calendar) -> String {
        if isCompleted, let completedAt, let date = WorkoutDate.parse(completedAt) { return WorkoutDate.day(date, calendar: calendar) }
        return date
    }
}
