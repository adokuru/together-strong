import Foundation
import Testing
@testable import TogetherStrong

@MainActor
func emptyWorkout() throws -> WorkoutDocument {
    try JSONDecoder().decode(WorkoutDocument.self, from: Data("{\"version\":1,\"rampSets\":2,\"sessions\":[]}".utf8))
}

@Suite(.serialized)
@MainActor
struct WorkoutLoggingTests {
    let now = Date(timeIntervalSince1970: 1793102400) // 27 October 2026, noon UTC.
    var calendar: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }

    @Test func sharedWebRuleFixturesAndExerciseContentAgree() throws {
        struct Fixtures: Decodable {
            struct Case: Decodable { let data: WorkoutDocument; let week: Int; let stage: String; let day: String? }
            struct SetCase: Decodable { struct Entry: Decodable { let reps: String; let kg: String; let done: Bool }; let set: Entry; let bodyweight: Bool; let valid: Bool }
            let now: String; let routines: [String: [Exercise]]; let cases: [Case]; let sets: [SetCase]
        }
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "workout-rules", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixtures.self, from: Data(contentsOf: url))
        let now = try #require(WorkoutDate.parse(fixture.now))
        for profile in Profile.allCases { #expect(Exercise.routine(profile) == fixture.routines[profile.rawValue]) }
        for sample in fixture.cases {
            #expect(sample.data.weekNumber(now: now) == sample.week)
            #expect((sample.data.sessions.first?.stage ?? "new") == sample.stage)
            #expect(sample.data.sessions.first?.day(calendar: calendar) == sample.day)
        }
        for sample in fixture.sets {
            let entry = SetEntry(fields: ["reps": .string(sample.set.reps), "kg": .string(sample.set.kg), "done": .bool(false)])
            #expect(entry.valid(bodyweight: sample.bodyweight) == sample.valid)
        }
    }

    @Test(arguments: [WarmupState.underway, .done, .skipped])
    func warmupPathsAndRepeatedStartStayOneEmptyDraft(_ warmup: WarmupState) throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .david, warmup: warmup, now: now, calendar: calendar)
        #expect(try data.start(profile: .david, now: now, calendar: calendar) == id)
        #expect(data.sessions.count == 1)
        #expect(data.session(id)?.warmup == warmup)
        #expect(data.session(id)?.stage == "draft")
        #expect(data.startedAt == nil)
        #expect(data.completedSessionCount == 0)
        #expect(data.session(id)?.sets("press").count == 2)
        #expect(data.session(id)?.sets("press").first?.kg == "")
    }

    @Test func firstCompletedSetStartsClockAndEditingClearsItsCompletion() throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .david, now: now, calendar: calendar)
        try data.editSet(id, exercise: "press", index: 0, reps: "10", kg: "12.50", now: now)
        #expect(data.startedAt == nil)
        try data.editSet(id, exercise: "press", index: 0, toggle: true, now: now)
        #expect(data.startedAt == WorkoutDate.timestamp(now))
        #expect(data.session(id)?.trainingStartedAt == WorkoutDate.timestamp(now))
        #expect(data.weekNumber(now: now.addingTimeInterval(15 * 86400)) == 3)
        try data.editSet(id, exercise: "press", index: 0, reps: "11", now: now)
        #expect(data.session(id)?.doneCount == 0)
        #expect(data.weekNumber(now: now.addingTimeInterval(15 * 86400)) == 1)
        #expect(data.completedSessionCount == 0)
    }

    @Test func emptyFinishIsRejectedAndEmptyPauseRemainsDraft() throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .mary, now: now, calendar: calendar)
        #expect(throws: WorkoutError.self) { try data.editSet(id, exercise: "row", index: 0, reps: "👨‍👩‍👧‍👦") }
        #expect(data.session(id)?.sets("row").first?.reps == "")
        #expect(throws: WorkoutError.self) { try data.finish(id, now: now) }
        try data.pause(id, now: now)
        #expect(data.session(id)?.stage == "draft")
        #expect(data.session(id)?.completedAt == nil)
        #expect(data.weekNumber(now: now.addingTimeInterval(30 * 86400)) == 1)
        #expect(data.completedSessionCount == 0)
    }

    @Test func olderDraftResumeKeepsItsIdentityDateAndEntries() throws {
        var data = try emptyWorkout()
        let earlier = now.addingTimeInterval(-5 * 86400)
        let id = try data.start(profile: .mary, now: earlier, calendar: calendar)
        try data.editSet(id, exercise: "row", index: 0, reps: "7", kg: "5", now: earlier)
        try data.pause(id, now: earlier)
        #expect(try data.start(profile: .mary, now: now, calendar: calendar) == id)
        #expect(data.session(id)?.date == WorkoutDate.day(earlier, calendar: calendar))
        #expect(data.session(id)?.sets("row").first?.reps == "7")
        #expect(data.sessions.count == 1)
    }

    @Test(arguments: Profile.allCases)
    func fullRoutineAfterRampUsesPersonalEmphasis(_ profile: Profile) throws {
        var data = try fixture().data
        let later = try #require(WorkoutDate.parse("2026-11-20T12:00:00.000Z"))
        let id = try data.start(profile: profile, now: later, calendar: calendar)
        #expect(data.session(id)?.sets(profile == .david ? "press" : "row").count == 3)
        #expect(data.session(id)?.totalCount == 15)
    }

    @Test func partialFinishIsIdempotentReadOnlyAndCanBeReopenedToday() throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .david, now: now, calendar: calendar)
        try data.editSet(id, exercise: "press", index: 0, reps: "10", kg: "0", now: now)
        try data.editSet(id, exercise: "press", index: 0, toggle: true, now: now)
        try data.finish(id, now: now)
        try data.finish(id, now: now.addingTimeInterval(100))
        #expect(data.session(id)?.doneCount == 1)
        #expect(data.session(id)?.totalCount == 14)
        #expect(data.session(id)?.completedAt == WorkoutDate.timestamp(now))
        #expect(data.completedSessionCount == 1)
        #expect(throws: WorkoutError.self) { try data.editSet(id, exercise: "press", index: 0, reps: "12") }
        try data.reopen(id, now: now, calendar: calendar)
        #expect(data.completedSessionCount == 0)
        try data.editSet(id, exercise: "press", index: 0, toggle: true, now: now)
        #expect(data.session(id)?.doneCount == 0)
    }

    @Test func discardAndRecoveryPreserveValuesAndPreventDateCollision() throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .david, now: now, calendar: calendar)
        try data.editSet(id, exercise: "press", index: 0, reps: "7")
        try data.discard(id, now: now)
        #expect(data.activeSession(now: now, calendar: calendar) == nil)
        let newer = try data.start(profile: .david, now: now, calendar: calendar)
        #expect(throws: WorkoutError.self) { try data.restoreDraft(id) }
        try data.discard(newer, now: now)
        try data.restoreDraft(id)
        #expect(data.activeSession(now: now, calendar: calendar)?.id == id)
        #expect(data.session(id)?.sets("press").first?.reps == "7")
        #expect(data.completedSessionCount == 0)
    }

    @Test func bodyweightCompletionNeedsRepsAndNoLoad() throws {
        var data = try emptyWorkout()
        let id = try data.start(profile: .david, now: now, calendar: calendar)
        #expect(throws: WorkoutError.self) { try data.editSet(id, exercise: "heel", index: 0, toggle: true) }
        try data.editSet(id, exercise: "heel", index: 0, reps: "8")
        try data.editSet(id, exercise: "heel", index: 0, toggle: true, now: now)
        #expect(data.session(id)?.sets("heel").first?.done == true)
        #expect(data.session(id)?.sets("heel").first?.kg == "")
    }

    @Test func finishDayUsesLocalCalendarWithoutRedatingOriginalSession() throws {
        var data = try emptyWorkout()
        let earlier = now.addingTimeInterval(-86400)
        let id = try data.start(profile: .mary, now: earlier, calendar: calendar)
        try data.editSet(id, exercise: "row", index: 0, reps: "10", kg: "5")
        try data.editSet(id, exercise: "row", index: 0, toggle: true, now: earlier)
        let finish = try #require(WorkoutDate.parse("2026-10-26T23:30:00.000Z"))
        try data.finish(id, now: finish)
        var lagos = calendar; lagos.timeZone = try #require(TimeZone(identifier: "Africa/Lagos"))
        #expect(data.session(id)?.day(calendar: lagos) == "2026-10-27")
        #expect(data.session(id)?.date == WorkoutDate.day(earlier, calendar: calendar))
    }

    @Test func editsDuringUploadSurviveAcknowledgmentAndSyncNext() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0))
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true), automaticSync: false)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""
        store.edit { id = try $0.start(profile: .david, now: now, calendar: calendar); try $0.editSet(id, exercise: "press", index: 0, reps: "10", kg: "5") }
        api.holdSave = true
        let syncing = Task { await store.sync() }
        for _ in 0..<1000 { if api.saveGate != nil { break }; await Task.yield() }
        let gate = try #require(api.saveGate)
        #expect(store.busy)
        #expect(store.edit { try $0.editSet(id, exercise: "press", index: 0, reps: "12") })
        api.holdSave = false; gate.resume(); await syncing.value
        #expect(store.record?.base.data.session(id)?.sets("press").first?.reps == "10")
        #expect(store.record?.local.session(id)?.sets("press").first?.reps == "12")
        #expect(store.dirty)
        await store.sync()
        #expect(!store.dirty)
        #expect(api.current.data.session(id)?.sets("press").first?.reps == "12")
        #expect(api.writes == 2)
    }

    @Test func failedSaveAndProcessRecreationKeepFullWorkout() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0))
        let sessions = MemorySessions(), repository = try WorkoutRepository(inMemory: true)
        let first = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false)
        await first.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""
        first.edit { id = try $0.start(profile: .mary, now: now, calendar: calendar); try $0.editSet(id, exercise: "row", index: 0, reps: "10", kg: "5"); try $0.editSet(id, exercise: "row", index: 0, toggle: true, now: now) }
        api.failBeforeSave = true; await first.sync()
        let restored = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false)
        await restored.restore()
        #expect(restored.record?.local.session(id)?.doneCount == 1)
        #expect(restored.dirty)
        api.failBeforeSave = false; await restored.sync()
        #expect(!restored.dirty)
        #expect(api.current.data.session(id)?.doneCount == 1)
    }

    @Test func conflictChoiceKeepsLocalWorkoutInRecoveryCopy() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0))
        let repository = try WorkoutRepository(inMemory: true), sessions = MemorySessions()
        let store = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        store.edit { let id = try $0.start(profile: .david, now: now, calendar: calendar); try $0.editSet(id, exercise: "press", index: 0, reps: "10", kg: "5") }
        let local = store.record?.local
        api.current.revision += 1
        await store.sync()
        #expect(store.conflict != nil)
        store.useCloudCopy()
        #expect(store.record?.recoveryCopy == local)
        #expect(!store.dirty)
        await store.refresh()
        #expect(store.record?.recoveryCopy == local)
        let relaunched = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false)
        await relaunched.restore()
        #expect(relaunched.record?.recoveryCopy == local)
    }
}
