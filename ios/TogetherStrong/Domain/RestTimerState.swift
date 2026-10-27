import Foundation

struct RestTimerState: Codable, Equatable {
    let sessionID: String
    let exerciseID: String
    private(set) var duration: Int
    private(set) var deadline: Date?
    private(set) var pausedRemaining: TimeInterval

    init(sessionID: String, exerciseID: String, duration: Int, now: Date = Date()) {
        self.sessionID = sessionID; self.exerciseID = exerciseID
        self.duration = min(3600, max(1, duration))
        pausedRemaining = Double(self.duration)
        deadline = now.addingTimeInterval(pausedRemaining)
    }
    func seconds(now: Date = Date()) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining) }
    func remaining(now: Date = Date()) -> Int { Int(ceil(seconds(now: now))) }
    func running(now: Date = Date()) -> Bool { deadline != nil && seconds(now: now) > 0 }
    func complete(now: Date = Date()) -> Bool { deadline != nil && seconds(now: now) == 0 }
    mutating func pause(now: Date = Date()) { pausedRemaining = seconds(now: now); deadline = nil }
    mutating func resume(now: Date = Date()) {
        let remaining = seconds(now: now)
        deadline = now.addingTimeInterval(remaining > 0 ? remaining : Double(duration))
    }
    mutating func addThirty(now: Date = Date()) {
        let remaining = min(3600, seconds(now: now) + 30)
        if deadline != nil { deadline = now.addingTimeInterval(remaining) }
        else { pausedRemaining = remaining }
    }
    mutating func reset(duration: Int? = nil) {
        if let duration { self.duration = min(3600, max(1, duration)) }
        deadline = nil; pausedRemaining = Double(self.duration)
    }
}
