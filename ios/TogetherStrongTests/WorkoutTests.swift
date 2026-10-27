import Foundation
import Testing
@testable import TogetherStrong

@MainActor
final class MemorySessions: SessionStoring {
    var token: String?
    func read() throws -> String? { token }
    func write(_ token: String) throws { self.token = token }
    func remove() throws { token = nil }
}

@MainActor
final class FakeAPI: WorkoutAPI {
    let origin = try! APIOrigin("https://native-tests.example.invalid")
    var current: WorkoutEnvelope
    var identity = Account(userId: "synthetic-first", profile: .david, needsPassword: false)
    var failAfterSave = false
    var revoked = false
    var writes = 0
    var holdSave = false
    var saveGate: CheckedContinuation<Void, Never>?
    var failBeforeSave = false
    init(_ envelope: WorkoutEnvelope) { current = envelope }
    func signIn(email: String, password: String) async throws -> String { "synthetic.signed" }
    func account(token: String) async throws -> Account {
        if revoked { throw APIError.unauthorized }
        return identity
    }
    func load(profile: Profile, token: String) async throws -> WorkoutEnvelope {
        if revoked { throw APIError.unauthorized }
        return current
    }
    func save(profile: Profile, data: WorkoutDocument, revision: Int, token: String) async throws -> Int {
        if holdSave { await withCheckedContinuation { saveGate = $0 } }
        if failBeforeSave { throw APIError.transport }
        guard revision == current.revision else { throw APIError.conflict }
        current = WorkoutEnvelope(data: data, revision: revision + 1)
        writes += 1
        if failAfterSave { failAfterSave = false; throw APIError.transport }
        return current.revision
    }
    func signOut(token: String) async throws { revoked = true }
}

@MainActor
func fixture() throws -> WorkoutEnvelope {
    let url = try #require(Bundle(for: FixtureBundle.self).url(forResource: "workout-v1", withExtension: "json"))
    return try JSONDecoder().decode(WorkoutEnvelope.self, from: Data(contentsOf: url))
}
final class FixtureBundle: NSObject {}

@Suite(.serialized)
@MainActor
struct WorkoutTests {
    @Test func realKeychainPersistsAndSeparatesAPIOrigins() throws {
        let service = "TogetherStrong.unit.\(UUID().uuidString)"
        let origin = try APIOrigin("https://first.example.invalid")
        let first = KeychainSessionStore(origin: origin, service: service)
        defer { try? first.remove() }
        try first.write("synthetic.signature")
        let restored = KeychainSessionStore(origin: origin, service: service)
        #expect(try restored.read() == "synthetic.signature")
        let other = KeychainSessionStore(origin: try APIOrigin("https://second.example.invalid"), service: service)
        #expect(try other.read() == nil)
        try restored.remove()
        #expect(try first.read() == nil)
    }

    @Test func documentRoundTripPreservesHistoryAndUnknownFields() throws {
        let original = try fixture()
        var edited = original.data
        edited.rampSets = 1
        var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
        let originalFields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original.data)) as? [String: Any])
        fields["rampSets"] = 2
        #expect(NSDictionary(dictionary: fields) == NSDictionary(dictionary: originalFields))
        #expect(original.data.completedSessionCount == 1)
        #expect(original.data.sessionCount == 1)
        #expect(try JSONDecoder().decode(WorkoutEnvelope.self, from: JSONEncoder().encode(original)) == original)
    }

    @Test func configurationRejectsCredentialsAndNonOriginURLs() throws {
        for value in ["https://user:secret@example.invalid", "https://example.invalid/path", "https://example.invalid?token=x", "http://remote.example.invalid", "file:///tmp/data"] {
            #expect(throws: APIError.configuration) { try APIOrigin(value) }
        }
        #expect(try APIOrigin("https://example.invalid").url.host == "example.invalid")
    }

    @Test func pendingPreferenceSurvivesStoreRecreationAndSyncsOnce() async throws {
        let api = FakeAPI(try fixture())
        let repository = try WorkoutRepository(inMemory: true)
        let sessions = MemorySessions()
        let first = WorkoutStore(api: api, sessions: sessions, repository: repository)
        await first.signIn(email: "synthetic@example.invalid", password: "unused")
        first.changeRampSets(1)
        #expect(first.dirty)
        let second = WorkoutStore(api: api, sessions: sessions, repository: repository)
        await second.restore()
        #expect(second.record?.local.rampSets == 1)
        #expect(second.dirty)
        await second.sync()
        #expect(!second.dirty)
        #expect(api.writes == 1)
        #expect(api.current.data.rampSets == 1)
    }

    @Test func lostResponseRecoversWithoutDuplicateWrite() async throws {
        let api = FakeAPI(try fixture())
        let sessions = MemorySessions()
        let repository = try WorkoutRepository(inMemory: true)
        let first = WorkoutStore(api: api, sessions: sessions, repository: repository)
        await first.signIn(email: "synthetic@example.invalid", password: "unused")
        first.changeRampSets(1)
        api.failAfterSave = true
        await first.sync()
        #expect(first.dirty)
        #expect(api.writes == 1)
        let relaunched = WorkoutStore(api: api, sessions: sessions, repository: repository)
        await relaunched.restore()
        await relaunched.sync()
        #expect(!relaunched.dirty)
        #expect(api.writes == 1)
    }

    @Test func conflictDoesNotOverwriteEitherCopy() async throws {
        let api = FakeAPI(try fixture())
        let store = WorkoutStore(api: api, sessions: MemorySessions(), repository: try WorkoutRepository(inMemory: true))
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        store.changeRampSets(1)
        api.current.revision += 1
        await store.sync()
        #expect(store.conflict != nil)
        #expect(store.record?.local.rampSets == 1)
        #expect(api.current.data.rampSets == 2)
        #expect(api.writes == 0)
        store.useCloudCopy()
        #expect(!store.dirty)
        #expect(store.record?.local.rampSets == 2)
    }

    @Test func revokedSessionRetainsPendingDataButHidesItUntilSameAccountSignsIn() async throws {
        let api = FakeAPI(try fixture())
        let sessions = MemorySessions()
        let store = WorkoutStore(api: api, sessions: sessions, repository: try WorkoutRepository(inMemory: true))
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        store.changeRampSets(1)
        api.revoked = true
        await store.refresh()
        #expect(store.account == nil)
        #expect(store.record == nil)
        #expect(sessions.token == nil)
        api.revoked = false
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        #expect(store.record?.local.rampSets == 1)
        api.identity = Account(userId: "synthetic-second", profile: .mary, needsPassword: false)
        let other = WorkoutStore(api: api, sessions: sessions, repository: try WorkoutRepository(inMemory: true))
        await other.signIn(email: "other@example.invalid", password: "unused")
        #expect(other.record?.local.rampSets == 2)
    }

    @Test func signOutClearsLocalAndSecureCopies() async throws {
        let api = FakeAPI(try fixture())
        let sessions = MemorySessions()
        let repository = try WorkoutRepository(inMemory: true)
        let store = WorkoutStore(api: api, sessions: sessions, repository: repository)
        await store.signIn(email: "synthetic@example.invalid", password: "unused")
        await store.signOut()
        #expect(api.revoked)
        #expect(store.account == nil)
        #expect(sessions.token == nil)
        #expect(try repository.read(key: api.origin.storageKey + "|synthetic-first") == nil)
    }
}
