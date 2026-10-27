import Foundation
import Testing
import UIKit
@testable import TogetherStrong

@MainActor
struct ProgressFixture: Decodable {
    struct Summary: Decodable { let workouts: Int; let sets: Int; let thisWeek: Int }
    let zone: String
    let now: String
    let data: WorkoutDocument
    let summary: Summary
    let weekly: [WeeklyWorkoutCount]
    let records: [String: [ExerciseRecord]]
    let days: [String: String]
    static func all() throws -> [ProgressFixture] {
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "workout-progress", withExtension: "json"))
        return try JSONDecoder().decode([ProgressFixture].self, from: Data(contentsOf: url))
    }
    var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!; return calendar }
    func progress() throws -> WorkoutProgress { WorkoutProgress(document: data, now: try #require(WorkoutDate.parse(now)), calendar: calendar) }
}

@Suite(.serialized)
@MainActor
struct WorkoutProgressTests {
    @Test func webAndSwiftAgreeOnCalendarSummaryAndEveryExerciseTrend() throws {
        for fixture in try ProgressFixture.all() {
            let progress = try fixture.progress()
            #expect(progress.completed.count == fixture.summary.workouts)
            #expect(progress.totalSets == fixture.summary.sets)
            #expect(progress.thisWeek == fixture.summary.thisWeek)
            #expect(progress.weekly == fixture.weekly)
            for exercise in Exercise.all { #expect(progress.records(for: exercise) == fixture.records[exercise.id]) }
            for session in fixture.data.sessions where !session.discarded { #expect(session.day(calendar: fixture.calendar) == fixture.days[session.id]) }
        }
    }

    @Test func completedTotalsExcludePausedDraftDiscardedAndEmptyFinishedSessions() throws {
        let fixture = try #require(ProgressFixture.all().first)
        let progress = try fixture.progress()
        #expect(progress.completed.count == 21)
        #expect(progress.totalSets == 78)
        #expect(progress.thisWeek == 2)
        #expect(progress.history.count == 24)
        #expect(!progress.history.contains { $0.id == "discarded" })
        #expect(!progress.completed.contains { ["draft", "paused", "empty-finish"].contains($0.id) })
    }

    @Test func calendarKeepsAllWorkoutsSharingACompletionDayAndDraftsKeepTheirDate() throws {
        let fixture = try #require(ProgressFixture.all().first)
        let progress = try fixture.progress()
        #expect(Set(progress.sessions(on: "2026-10-26").map(\.id)) == Set(["late-finish", "completed-18"]))
        #expect(progress.sessions(on: "2026-10-20").isEmpty)
        #expect(progress.sessions(on: "2026-10-27").first?.id == "paused")
        let lagos = try #require(ProgressFixture.all().first { $0.zone == "Africa/Lagos" }).progress()
        #expect(lagos.sessions(on: "2026-10-27").count == 2)
        #expect(lagos.sessions(on: "2026-10-26").count == 1)
    }

    @Test func bestSetUsesLoadThenRepsAndBodyweightUsesRepsWithChronologicalDates() throws {
        let fixture = try #require(ProgressFixture.all().first), progress = try fixture.progress()
        let press = progress.records(for: Exercise.all[0])
        #expect(press.count == 20)
        #expect(press.first == ExerciseRecord(sessionID: "completed-0", date: "2026-09-01", value: 0, reps: 12))
        #expect(press.last?.value == 0)
        #expect(press.allSatisfy { $0.value < 100 })
        #expect(press.map(\.date) == press.map(\.date).sorted())
        let heel = progress.records(for: try #require(Exercise.all.first { $0.id == "heel" }))
        #expect(heel.count == 19 && heel[4].value == 10 && heel[4].reps == 10)
        #expect(progress.records(for: try #require(Exercise.all.first { $0.id == "curl" })).isEmpty)
        let row = progress.records(for: try #require(Exercise.all.first { $0.id == "row" }))
        #expect(row.first?.date == "2026-10-20" && row.first?.value == 7.5)
    }

    @Test func mondayWeeksHonorDSTAndLocalCompletionDate() throws {
        let cases = try ProgressFixture.all()
        let ny = try #require(cases.first { $0.zone == "America/New_York" }).progress()
        let pacific = try #require(cases.first { $0.zone == "Pacific/Kiritimati" }).progress()
        #expect(ny.weekly.last?.date == "2026-11-02" && ny.thisWeek == 0)
        #expect(ny.weekly.dropLast().last?.count == 3)
        #expect(pacific.weekly.last?.date == "2026-11-02" && pacific.thisWeek == 1)
    }

    @Test func emptyHistoryProducesEightZeroWeeksAndNoFalseProgress() throws {
        let fixture = try #require(ProgressFixture.all().last), progress = try fixture.progress()
        #expect(progress.completed.isEmpty && progress.history.isEmpty && progress.totalSets == 0 && progress.thisWeek == 0)
        #expect(progress.weekly.count == 8 && progress.weekly.allSatisfy { $0.count == 0 })
        #expect(progress.records(for: Exercise.all[0]).isEmpty)
        #expect(WorkoutDate.date("2026-02-30") == nil)
        #expect(WorkoutDate.date("2028-02-29") != nil)
    }

    @Test func finishReopenAndRestoreRecalculateFromLocalCopyWithoutCountingTwice() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0)), repository = try WorkoutRepository(inMemory: true), sessions = MemorySessions()
        let store = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false, restAlerts: FakeRestAlerts())
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""
        store.edit { id = try $0.start(profile: .david); try $0.editSet(id, exercise: "press", index: 0, reps: "10", kg: "5"); try $0.editSet(id, exercise: "press", index: 0, toggle: true) }
        #expect(WorkoutProgress(document: try #require(store.record?.local)).totalSets == 0)
        store.edit { try $0.finish(id); try $0.finish(id) }
        #expect(WorkoutProgress(document: try #require(store.record?.local)).totalSets == 1)
        #expect(store.progressStatus.contains("waiting to sync"))
        let restored = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false, restAlerts: FakeRestAlerts())
        await restored.restore()
        #expect(WorkoutProgress(document: try #require(restored.record?.local)).completed.count == 1)
        restored.edit { try $0.reopen(id) }
        #expect(WorkoutProgress(document: try #require(restored.record?.local)).completed.isEmpty)
        #expect(WorkoutProgress(document: try #require(restored.record?.local)).records(for: Exercise.all[0]).isEmpty)
    }

    @Test func fullHistoryKeepsAllThousandSessionsWhileChartsCanShowRecentRecords() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = try #require(WorkoutDate.date("2022-01-01", calendar: calendar))
        var document = try emptyWorkout()
        document.sessions = (0..<1000).map { index in
            let date = calendar.date(byAdding: .day, value: index, to: start)!
            var session = WorkoutSession(profile: .david, rampSets: 1, week: 1, now: date, calendar: calendar)
            session.set("id", .string("history-\(index)"))
            var set = SetEntry.empty; set.reps = "10"; set.kg = "5"; set.done = true
            session.replaceSets("press", [set]); session.set("completedAt", .string(WorkoutDate.timestamp(date)))
            return session
        }
        let progress = WorkoutProgress(document: document, calendar: calendar)
        #expect(progress.history.count == 1000 && progress.totalSets == 1000)
        #expect(progress.records(for: Exercise.all[0]).count == 1000)
        #expect(progress.sessions(on: "2022-01-01").first?.id == "history-0")
        #expect(progress.days.count == 1000 && progress.weekly.count == 8)
        #expect(document.sessionCount == 1000)
    }

    @Test func historyAndChartsAreReadOnlyAndUseTheAuthenticatedAccountsCopy() async throws {
        let sample = try #require(ProgressFixture.all().first)
        let api = FakeAPI(WorkoutEnvelope(data: sample.data, revision: 0))
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true), automaticSync: false, restAlerts: FakeRestAlerts())
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        let before = store.record
        let history = SessionListViewController(store: store); history.loadViewIfNeeded(); history.viewWillAppear(false)
        let progress = ProgressViewController(store: store); progress.loadViewIfNeeded(); progress.viewWillAppear(false)
        let selection = UICalendarSelectionSingleDate(delegate: history)
        history.dateSelection(selection, didSelectDate: DateComponents(year: 2026, month: 10, day: 26))
        #expect(store.record == before && api.writes == 0)
        history.viewDidDisappear(false); progress.viewDidDisappear(false)
        api.identity = Account(userId: "synthetic-second", profile: .mary, needsPassword: false)
        api.current = WorkoutEnvelope(data: try emptyWorkout(), revision: 0)
        await store.signIn(email: "other@example.invalid", password: "unused")
        #expect(WorkoutProgress(document: try #require(store.record?.local)).completed.isEmpty)
    }
}
