import Foundation
import Testing
import UserNotifications
import UIKit
@testable import TogetherStrong

@MainActor
final class FakeRestAlerts: RestAlertScheduling {
    var granted = false
    var permissionRequests = 0
    var holdPermission = false
    var gate: CheckedContinuation<Bool, Never>?
    var deadline: Date?
    var enabled = false
    func requestPermission() async throws -> Bool {
        permissionRequests += 1
        if holdPermission { return await withCheckedContinuation { gate = $0 } }
        return granted
    }
    func update(deadline: Date?, enabled: Bool) { self.deadline = deadline; self.enabled = enabled }
}

@Suite(.serialized)
@MainActor
struct RestAndGuideTests {
    let now = Date(timeIntervalSince1970: 1793102400)

    @Test func timerUsesDeadlineAndPreservesFractionalPause() throws {
        var timer = RestTimerState(sessionID: "test", exerciseID: "press", duration: 120, now: now)
        #expect(timer.remaining(now: now.addingTimeInterval(0.2)) == 120)
        timer.pause(now: now.addingTimeInterval(10.25))
        #expect(timer.deadline == nil)
        #expect(timer.seconds(now: now.addingTimeInterval(1000)) == 109.75)
        timer.resume(now: now.addingTimeInterval(1000))
        #expect(timer.deadline == now.addingTimeInterval(1109.75))
        let restored = try JSONDecoder().decode(RestTimerState.self, from: JSONEncoder().encode(timer))
        #expect(restored.remaining(now: now.addingTimeInterval(1100)) == 10)
        #expect(restored.complete(now: now.addingTimeInterval(1200)))
        #expect(restored.remaining(now: now.addingTimeInterval(1200)) == 0)
    }

    @Test func timerAddResetPresetsAndExpiryRestart() {
        var timer = RestTimerState(sessionID: "test", exerciseID: "press", duration: 90, now: now)
        timer.addThirty(now: now.addingTimeInterval(10))
        #expect(timer.remaining(now: now.addingTimeInterval(10)) == 110)
        timer.pause(now: now.addingTimeInterval(10)); timer.addThirty(now: now)
        #expect(timer.remaining(now: now) == 140)
        for preset in [60,90,120] {
            timer.reset(duration: preset)
            #expect(!timer.running(now: now)); #expect(timer.remaining(now: now) == preset)
        }
        timer.resume(now: now)
        timer.resume(now: now.addingTimeInterval(200))
        #expect(timer.remaining(now: now.addingTimeInterval(200)) == 120)
        timer.addThirty(now: now.addingTimeInterval(400))
        #expect(timer.remaining(now: now.addingTimeInterval(400)) == 30)
        timer.reset(duration: 9999); timer.addThirty(now: now)
        #expect(timer.remaining(now: now) == 3600)
        timer.reset(duration: 0); #expect(timer.remaining(now: now) == 1)
    }

    @Test func timerDoesNotChangeWorkoutOrUploadAndRestoresWithAccount() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0))
        let sessions = MemorySessions(), repository = try WorkoutRepository(inMemory: true), alerts = FakeRestAlerts()
        let store = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false, restAlerts: alerts)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""
        store.edit { id = try $0.start(profile: .david, now: now) }
        await store.sync()
        let before = store.record?.local, press = try #require(Exercise.all.first { $0.id == "press" })
        #expect(store.startRest(sessionID: id, exercise: press, now: now))
        #expect(alerts.permissionRequests == 0)
        #expect(store.record?.local == before); #expect(!store.dirty)
        #expect(store.record?.local.startedAt == nil); #expect(store.record?.local.completedSessionCount == 0)
        let deadline = store.record?.restTimer?.deadline
        store.changeRampSets(1); await store.sync()
        #expect(store.record?.restTimer?.deadline == deadline)
        let restored = WorkoutStore(api: api, sessions: sessions, repository: repository, automaticSync: false, restAlerts: alerts)
        await restored.restore()
        #expect(restored.record?.restTimer?.deadline == deadline)
        #expect(restored.record?.restTimer?.complete(now: now.addingTimeInterval(500)) == true)
        api.identity = Account(userId: "synthetic-second", profile: .mary, needsPassword: false)
        await restored.signIn(email: "other@example.invalid", password: "unused")
        #expect(restored.record?.restTimer == nil)
        #expect(!alerts.enabled && alerts.deadline == nil)
        let wire = String(decoding: try JSONEncoder().encode(api.current.data), as: UTF8.self)
        #expect(!wire.contains("restTimer")); #expect(!wire.contains("restAlerts"))
    }

    @Test(arguments: ["pause","finish","discard","cloud-finish","logout","revoked"])
    func endingWorkoutOrAuthenticationCancelsRest(_ action: String) async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0))
        let alerts = FakeRestAlerts(); alerts.granted = true
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true), automaticSync: false, restAlerts: alerts)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""
        store.edit {
            id = try $0.start(profile: .david, now: now)
            try $0.editSet(id, exercise: "press", index: 0, reps: "10", kg: "5")
            try $0.editSet(id, exercise: "press", index: 0, toggle: true, now: now)
        }
        await store.sync()
        #expect(await store.enableRestAlerts())
        #expect(store.startRest(sessionID: id, exercise: Exercise.all[0]))
        #expect(alerts.enabled && alerts.deadline != nil)
        switch action {
        case "pause": store.edit { try $0.pause(id) }
        case "finish": store.edit { try $0.finish(id) }
        case "discard": store.edit { try $0.editSet(id, exercise: "press", index: 0, toggle: true); try $0.discard(id) }
        case "cloud-finish": try api.current.data.finish(id); api.current.revision += 1; await store.refresh()
        case "logout": await store.signOut()
        default: api.revoked = true; await store.refresh()
        }
        #expect(store.record?.restTimer == nil)
        #expect(alerts.deadline == nil)
        if action == "logout" || action == "revoked" { #expect(!alerts.enabled) }
    }

    @Test func timerChangesDuringUploadSurviveAcknowledgment() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0)), alerts = FakeRestAlerts()
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true), automaticSync: false, restAlerts: alerts)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""; store.edit { id = try $0.start(profile: .david, now: now) }
        api.holdSave = true
        let syncing = Task { await store.sync() }
        for _ in 0..<1000 { if api.saveGate != nil { break }; await Task.yield() }
        let gate = try #require(api.saveGate)
        #expect(store.startRest(sessionID: id, exercise: Exercise.all[0], now: now))
        #expect(store.changeRest { $0.pause(now: now.addingTimeInterval(10)); $0.addThirty(now: now) })
        let timer = store.record?.restTimer
        api.holdSave = false; gate.resume(); await syncing.value
        #expect(store.record?.restTimer == timer)
        #expect(store.record?.restTimer?.remaining(now: now) == 140)
        #expect(!store.dirty)
    }

    @Test func deniedPermissionDoesNotInterruptTimerAndPendingGrantCannotLeakAcrossAccounts() async throws {
        let api = FakeAPI(WorkoutEnvelope(data: try emptyWorkout(), revision: 0)), alerts = FakeRestAlerts()
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true), automaticSync: false, restAlerts: alerts)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        var id = ""; store.edit { id = try $0.start(profile: .david, now: now) }
        store.startRest(sessionID: id, exercise: Exercise.all[0], now: now)
        let timer = store.record?.restTimer
        #expect(await store.enableRestAlerts() == false)
        #expect(store.record?.restTimer == timer)
        #expect(!alerts.enabled)
        alerts.granted = true
        #expect(await store.enableRestAlerts())
        #expect(store.disableRestAlerts())
        #expect(!alerts.enabled && store.record?.restAlertsEnabled == false)
        #expect(store.record?.restTimer == timer)
        alerts.holdPermission = true
        let request = Task { await store.enableRestAlerts() }
        for _ in 0..<1000 { if alerts.gate != nil { break }; await Task.yield() }
        let gate = try #require(alerts.gate)
        await store.signOut(localOnly: true)
        api.identity = Account(userId: "synthetic-second", profile: .mary, needsPassword: false)
        await store.signIn(email: "other@example.invalid", password: "unused")
        gate.resume(returning: true)
        #expect(await request.value == false)
        #expect(store.record?.restAlertsEnabled != true)
    }

    @Test func oldSnapshotsDecodeAndNotificationHasOnePrivateUTCDeadline() throws {
        let data = try emptyWorkout(), envelope = WorkoutEnvelope(data: data, revision: 0)
        let legacy = try JSONSerialization.data(withJSONObject: ["base":JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)), "local":JSONSerialization.jsonObject(with: JSONEncoder().encode(data))])
        let decoded = try JSONDecoder().decode(SyncRecord.self, from: legacy)
        #expect(decoded.restTimer == nil && decoded.restAlertsEnabled == nil)
        let deadline = now.addingTimeInterval(120.1), request = LocalRestAlerts.request(deadline: deadline)
        let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.timeZone?.secondsFromGMT() == 0)
        let date = try #require(trigger.dateComponents.calendar?.date(from: trigger.dateComponents))
        #expect(date == now.addingTimeInterval(121))
        #expect(request.identifier == LocalRestAlerts.identifier)
        #expect(request.content.title == "Rest complete")
        #expect(request.content.userInfo.isEmpty)
    }

    @Test func everyNativeMotionMatchesWebReferencePoses() throws {
        struct Sample: Decodable {
            struct Pose: Decodable { let head: [Double]; let body: String; let arms: [String]; let legs: [String]; let weights: [[Double]] }
            let id: String; let progress: Double; let pose: Pose
        }
        let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "exercise-motion", withExtension: "json"))
        let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: url))
        #expect(samples.count == 147)
        func points(_ text: String) -> [PosePoint] {
            text.split(separator: " ").map { pair in let xy = pair.split(separator: ",").compactMap { Double($0) }; return PosePoint(xy[0],xy[1]) }
        }
        func close(_ actual: [PosePoint], _ expected: [PosePoint]) {
            #expect(actual.count == expected.count)
            for (a,b) in zip(actual,expected) { #expect(abs(a.x-b.x) <= 0.00051 && abs(a.y-b.y) <= 0.00051) }
        }
        for sample in samples {
            let pose = ExercisePose.make(sample.id, progress: sample.progress)
            close([pose.head], [PosePoint(sample.pose.head[0],sample.pose.head[1])])
            close(pose.body,points(sample.pose.body))
            #expect(pose.arms.count == sample.pose.arms.count && pose.legs.count == sample.pose.legs.count)
            for (a,b) in zip(pose.arms,sample.pose.arms) { close(a,points(b)) }
            for (a,b) in zip(pose.legs,sample.pose.legs) { close(a,points(b)) }
            close(pose.weights,sample.pose.weights.map { PosePoint($0[0],$0[1]) })
        }
        for exercise in Exercise.all {
            let info = try #require(ExerciseGuideInfo.all[exercise.id])
            #expect(URL(string: info.reference)?.scheme == "https")
            #expect(!info.cue.isEmpty && !info.camera.isEmpty)
        }
    }

    @Test func limbsStayRigidAndFeetStayGroundedAcrossMotion() {
        func length(_ a: PosePoint, _ b: PosePoint) -> Double { hypot(a.x-b.x,a.y-b.y) }
        for id in ["press","row","squat","rdl","curl","kickback","heel"] {
            let start = ExercisePose.make(id, progress: 0)
            for step in 0...100 {
                let pose = ExercisePose.make(id, progress: Double(step)/100)
                for (limb,original) in zip(pose.arms+pose.legs,start.arms+start.legs) {
                    for index in 1..<limb.count { #expect(abs(length(limb[index-1],limb[index])-length(original[index-1],original[index])) < 0.000001) }
                }
                for leg in pose.legs { #expect(leg.last?.y == 122) }
            }
        }
    }

    @Test func playbackIsOptInAndControllable() {
        var slow = GuidePlayback(), normal = GuidePlayback()
        slow.advance(seconds: 0.1); #expect(slow.progress == 0 && !slow.playing)
        slow.play(); normal.speed = 1; normal.play()
        for _ in 0..<30 { slow.advance(seconds: 0.1); normal.advance(seconds: 0.1) }
        #expect(abs(slow.progress-0.5) < 0.000001); #expect(abs(normal.progress-1) < 0.000001)
        normal.scrub(0.25); #expect(!normal.playing && normal.progress == 0.25)
        normal.play(); normal.pause()
        normal.advance(seconds: 100); #expect(!normal.playing && normal.progress == 0.25)
        normal.scrub(5); #expect(normal.progress == 1)
        normal.scrub(-2); #expect(normal.progress == 0)
        normal.play(); normal.advance(seconds: 100)
        #expect(normal.progress < 0.01) // A stalled frame never jumps a full demonstration.
    }

    @Test func guidePausesOnBackgroundReduceMotionChangeAndDismissal() async throws {
        let guide = ExerciseGuideViewController(exercise: Exercise.all[0])
        guide.loadViewIfNeeded(); guide.viewWillAppear(false)
        defer { guide.viewWillDisappear(false); guide.viewDidDisappear(false) }
        func descendants(_ view: UIView) -> [UIView] { [view] + view.subviews.flatMap(descendants) }
        let play = try #require(descendants(guide.view).first { $0.accessibilityIdentifier == "guidePlay" } as? UIButton)
        #expect(!play.isSelected)
        for event in [UIApplication.willResignActiveNotification, UIAccessibility.reduceMotionStatusDidChangeNotification] {
            play.sendActions(for: .touchUpInside); #expect(play.isSelected)
            NotificationCenter.default.post(name: event, object: nil)
            for _ in 0..<100 { if !play.isSelected { break }; await Task.yield() }
            #expect(!play.isSelected)
            NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
            for _ in 0..<10 { await Task.yield() }
            #expect(!play.isSelected)
        }
        play.sendActions(for: .touchUpInside); #expect(play.isSelected)
        guide.viewWillDisappear(false); #expect(!play.isSelected)
    }
}
