import Foundation

enum APIError: Error, LocalizedError, Equatable {
    case configuration, unauthorized, forbidden, conflict, invalidDocument, invalidResponse
    case rejected(Int), transport

    var errorDescription: String? {
        switch self {
        case .configuration: "The server connection is not configured."
        case .unauthorized: "Your sign-in expired or the details were not accepted. Please sign in again."
        case .forbidden: "This account cannot access that profile."
        case .conflict: "Your workout changed on another device. Your changes on this iPhone are preserved."
        case .invalidDocument: "This workout format is not supported. Your saved copy has been preserved."
        case .invalidResponse: "The server returned an unexpected response. Please retry."
        case .rejected(let status) where status == 429: "Too many attempts. Please wait a moment and retry."
        case .rejected: "The server could not save this change. Please retry."
        case .transport: "Could not reach the server. Please check your connection and retry."
        }
    }
}

struct APIOrigin: Equatable {
    let url: URL

    init(_ value: String) throws {
        guard let parts = URLComponents(string: value), let url = parts.url,
              let host = parts.host, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError.configuration }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        #if DEBUG
        guard parts.scheme == "https" || (parts.scheme == "http" && local) else { throw APIError.configuration }
        #else
        guard parts.scheme == "https", !local else { throw APIError.configuration }
        #endif
        self.url = url
    }

    var storageKey: String { url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
protocol WorkoutAPI: AnyObject {
    var origin: APIOrigin { get }
    func signIn(email: String, password: String) async throws -> String
    func account(token: String) async throws -> Account
    func load(profile: Profile, token: String) async throws -> WorkoutEnvelope
    func save(profile: Profile, data: WorkoutDocument, revision: Int, token: String) async throws -> Int
    func signOut(token: String) async throws
}

@MainActor
final class APIClient: WorkoutAPI {
    let origin: APIOrigin
    private let session: URLSession

    init(origin: APIOrigin, session: URLSession? = nil) {
        self.origin = origin
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpCookieStorage = nil
            config.httpShouldSetCookies = false
            config.urlCache = nil
            config.timeoutIntervalForRequest = 25
            self.session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
        }
    }

    private func send(_ path: String, method: String = "GET", token: String? = nil,
                      body: Data? = nil, query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        guard var components = URLComponents(url: origin.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw APIError.configuration }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.configuration }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw APIError.transport }
        guard let response = result.1 as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch response.statusCode {
        case 200..<300: return (result.0, response)
        case 401: throw APIError.unauthorized
        case 403: throw APIError.forbidden
        case 409: throw APIError.conflict
        default: throw APIError.rejected(response.statusCode)
        }
    }

    func signIn(email: String, password: String) async throws -> String {
        struct Body: Encodable { let email: String; let password: String }
        let (_, response) = try await send("api/auth/sign-in/email", method: "POST",
            body: JSONEncoder().encode(Body(email: email, password: password)))
        guard let token = response.value(forHTTPHeaderField: "set-auth-token"),
              token.contains("."), !token.contains(where: \.isWhitespace) else { throw APIError.invalidResponse }
        return token
    }

    func account(token: String) async throws -> Account {
        let (data, _) = try await send("api/account", token: token)
        return try JSONDecoder().decode(Account.self, from: data)
    }

    func load(profile: Profile, token: String) async throws -> WorkoutEnvelope {
        let (data, _) = try await send("api/workouts", token: token,
            query: [URLQueryItem(name: "profile", value: profile.rawValue)])
        let envelope = try JSONDecoder().decode(WorkoutEnvelope.self, from: data)
        guard envelope.revision >= 0 else { throw APIError.invalidResponse }
        return envelope
    }

    func save(profile: Profile, data: WorkoutDocument, revision: Int, token: String) async throws -> Int {
        struct Body: Encodable { let profile: Profile; let data: WorkoutDocument; let revision: Int }
        struct Result: Decodable { let revision: Int }
        let body = try JSONEncoder().encode(Body(profile: profile, data: data, revision: revision))
        let (response, _) = try await send("api/workouts", method: "PUT", token: token, body: body)
        let next = try JSONDecoder().decode(Result.self, from: response).revision
        guard next == revision + 1 else { throw APIError.invalidResponse }
        return next
    }

    func signOut(token: String) async throws {
        _ = try await send("api/auth/sign-out", method: "POST", token: token, body: Data("{}".utf8))
    }
}
