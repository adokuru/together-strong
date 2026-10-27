import Foundation
import Testing
@testable import TogetherStrong

nonisolated final class StubQueue: @unchecked Sendable {
    struct Response: Sendable { let status: Int; let headers: [String: String]; let data: Data }
    private let lock = NSLock()
    private var response = Response(status: 200, headers: [:], data: Data())
    private var captured: URLRequest?
    func set(status: Int, headers: [String: String] = [:], json: String = "{}") {
        lock.withLock { response = Response(status: status, headers: headers, data: Data(json.utf8)); captured = nil }
    }
    func receive(_ request: URLRequest) -> Response { lock.withLock { captured = request; return response } }
    var request: URLRequest? { lock.withLock { captured } }
}

nonisolated final class StubProtocol: URLProtocol {
    static let queue = StubQueue()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = Self.queue.receive(request)
        guard let url = request.url, let http = HTTPURLResponse(url: url, statusCode: response.status, httpVersion: nil, headerFields: response.headers) else { return }
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
@MainActor
struct APIClientTests {
    func client() throws -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        config.httpCookieStorage = nil; config.httpShouldSetCookies = false
        return APIClient(origin: try APIOrigin("https://native-tests.example.invalid"), session: URLSession(configuration: config))
    }

    @Test func nativeSignInReadsSignedHeaderWithoutSendingCookies() async throws {
        StubProtocol.queue.set(status: 200, headers: ["set-auth-token": "synthetic.signature"])
        let token = try await client().signIn(email: "synthetic@example.invalid", password: "unused")
        #expect(token == "synthetic.signature")
        let request = try #require(StubProtocol.queue.request)
        #expect(request.url?.path == "/api/auth/sign-in/email")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Origin") == nil)
        #expect(request.httpMethod == "POST")
    }

    @Test func nativeRequestsCarryBearerAndCorrectProfile() async throws {
        StubProtocol.queue.set(status: 200, json: "{\"data\":{\"version\":1,\"rampSets\":2,\"sessions\":[]},\"revision\":0}")
        let envelope = try await client().load(profile: .mary, token: "synthetic.signature")
        let request = try #require(StubProtocol.queue.request)
        #expect(request.url?.query == "profile=Mary")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic.signature")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(envelope.revision == 0)
    }

    @Test func nativeErrorsAreTypedAndNeverLeakResponseText() async throws {
        for (status, expected) in [(401, APIError.unauthorized), (403, .forbidden), (409, .conflict), (429, .rejected(429)), (302, .rejected(302))] {
            StubProtocol.queue.set(status: status, json: "{\"error\":\"private-server-detail\"}")
            await #expect(throws: expected) { try await client().account(token: "synthetic.signature") }
            #expect(!expected.localizedDescription.contains("private-server-detail"))
        }
    }

    @Test func missingSignedTokenAndUnsupportedDocumentsAreRejected() async throws {
        StubProtocol.queue.set(status: 200)
        await #expect(throws: APIError.invalidResponse) { try await client().signIn(email: "synthetic@example.invalid", password: "unused") }
        StubProtocol.queue.set(status: 200, json: "{\"data\":{\"version\":2,\"rampSets\":2,\"sessions\":[]},\"revision\":0}")
        await #expect(throws: APIError.invalidDocument) { try await client().load(profile: .david, token: "synthetic.signature") }
    }
}
