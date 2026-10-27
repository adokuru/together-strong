import Foundation

struct ExerciseRecord: Codable, Equatable {
    let sessionID: String
    let date: String
    let value: Double
    let reps: Int
}

struct WeeklyWorkoutCount: Codable, Equatable {
    let date: String
    let count: Int
}

struct WorkoutProgress {
    let document: WorkoutDocument
    let calendar: Calendar
    let completed: [WorkoutSession]
    let thisWeek: Int
    let weekly: [WeeklyWorkoutCount]
    let history: [WorkoutSession]
    private let sessionsByDay: [String: [WorkoutSession]]
    var totalSets: Int { completed.reduce(0) { $0 + $1.doneCount } }
    var days: Set<String> { Set(sessionsByDay.keys) }

    init(document: WorkoutDocument, now: Date = Date(), calendar: Calendar = WorkoutDate.calendar) {
        self.document = document; self.calendar = calendar
        let available = document.sessions.filter { !$0.discarded }
        let days = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0.day(calendar: calendar)) })
        let history = available.sorted { a, b in days[a.id] == days[b.id] ? a.date > b.date : days[a.id]! > days[b.id]! }
        self.history = history
        sessionsByDay = Dictionary(grouping: history) { days[$0.id]! }
        let completed = available.filter(\.isCompleted)
        self.completed = completed
        let completedDays = completed.map { days[$0.id]! }
        let today = calendar.startOfDay(for: now)
        let offset = (calendar.component(.weekday, from: today) + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -offset, to: today)!
        let start = WorkoutDate.day(monday, calendar: calendar)
        let end = WorkoutDate.day(calendar.date(byAdding: .day, value: 7, to: monday)!, calendar: calendar)
        thisWeek = completedDays.filter { $0 >= start && $0 < end }.count
        weekly = (0..<8).map { index in
            let date = calendar.date(byAdding: .day, value: (index - 7) * 7, to: monday)!
            let start = WorkoutDate.day(date, calendar: calendar)
            let end = WorkoutDate.day(calendar.date(byAdding: .day, value: 7, to: date)!, calendar: calendar)
            return WeeklyWorkoutCount(date: start, count: completedDays.filter { $0 >= start && $0 < end }.count)
        }
    }

    func sessions(on day: String) -> [WorkoutSession] { sessionsByDay[day] ?? [] }
    func records(for exercise: Exercise) -> [ExerciseRecord] {
        completed.compactMap { session in
            let best = session.sets(exercise.id).filter(\.done).max { a, b in
                if exercise.bodyweight { return (Int(a.reps) ?? 0) < (Int(b.reps) ?? 0) }
                let akg = Double(a.kg) ?? 0, bkg = Double(b.kg) ?? 0
                return akg == bkg ? (Int(a.reps) ?? 0) < (Int(b.reps) ?? 0) : akg < bkg
            }
            guard let best, let reps = Int(best.reps) else { return nil }
            return ExerciseRecord(sessionID: session.id, date: session.date, value: exercise.bodyweight ? Double(reps) : Double(best.kg) ?? 0, reps: reps)
        }.sorted { $0.date == $1.date ? $0.sessionID < $1.sessionID : $0.date < $1.date }
    }
}

extension WorkoutDate {
    static func date(_ day: String, calendar: Calendar = WorkoutDate.calendar) -> Date? {
        let values = day.split(separator: "-").compactMap { Int($0) }
        guard values.count == 3 else { return nil }
        var components = DateComponents(); components.calendar = calendar; components.timeZone = calendar.timeZone
        components.year = values[0]; components.month = values[1]; components.day = values[2]; components.hour = 12
        guard let date = calendar.date(from: components), self.day(date, calendar: calendar) == day else { return nil }
        return date
    }
    static func display(_ day: String, short: Bool = false) -> String {
        guard let date = date(day) else { return day }
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(short ? "dMMM" : "EEE dMMMyyyy")
        return formatter.string(from: date)
    }
}

extension WorkoutStore {
    var progressStatus: String {
        if conflict != nil { return "Includes changes on this iPhone. Cloud conflict needs review on the home screen." }
        if dirty { return "Includes changes saved on this iPhone, waiting to sync." }
        if busy { return "Refreshing saved workouts…" }
        if let message, message != "Synced securely.", message != "Saved on this iPhone." { return message }
        return "Synced securely. Only your own workouts are shown."
    }
}
