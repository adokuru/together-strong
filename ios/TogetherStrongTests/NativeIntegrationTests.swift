import Foundation
import Testing
@testable import TogetherStrong

nonisolated struct LiveConfig: Decodable {
    let origin: String
    let emails: [String]
    let password: String
    static var path: String? {
        guard let path = ProcessInfo.processInfo.environment["TS_LIVE_CONFIG"],
              path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        return path
    }
}

@Suite(.serialized)
@MainActor
struct NativeIntegrationTests {
    @Test(.enabled(if: LiveConfig.path != nil))
    func realBackendAuthenticationAndWorkoutRoundTrip() async throws {
        let config = try JSONDecoder().decode(LiveConfig.self, from: Data(contentsOf: URL(fileURLWithPath: try #require(LiveConfig.path))))
        let origin = try APIOrigin(config.origin)
        #expect(["127.0.0.1", "localhost"].contains(origin.url.host ?? ""))
        let api = APIClient(origin: origin)
        let token = try await api.signIn(email: config.emails[0], password: config.password)
        let account = try await api.account(token: token)
        #expect(account.profile == .david)
        #expect(!account.needsPassword)
        let secure = KeychainSessionStore(origin: origin, service: "TogetherStrong.test.\(UUID().uuidString)")
        defer { try? secure.remove() }
        try secure.write(token)
        #expect(try secure.read() == token)
        let before = try await api.load(profile: .david, token: token)
        let sample = try fixture().data
        let revision = try await api.save(profile: .david, data: sample, revision: before.revision, token: token)
        let after = try await api.load(profile: .david, token: try #require(secure.read()))
        #expect(after.data == sample)
        #expect(after.revision == revision)
        await #expect(throws: APIError.conflict) {
            try await api.save(profile: .david, data: sample, revision: before.revision, token: token)
        }
        await #expect(throws: APIError.forbidden) { try await api.load(profile: .mary, token: token) }
        _ = try await api.save(profile: .david, data: before.data, revision: revision, token: token)
        let otherToken = try await api.signIn(email: config.emails[1], password: config.password)
        #expect(try await api.account(token: otherToken).profile == .mary)
        await #expect(throws: APIError.forbidden) { try await api.load(profile: .david, token: otherToken) }
        try await api.signOut(token: otherToken)
        try await api.signOut(token: token)
        await #expect(throws: APIError.unauthorized) { try await api.account(token: token) }
    }
}
