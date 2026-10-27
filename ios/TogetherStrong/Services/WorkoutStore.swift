import Foundation

@MainActor
final class WorkoutStore {
    let api: any WorkoutAPI
    private let sessions: any SessionStoring
    private let repository: WorkoutRepository
    private var token: String?
    private(set) var account: Account?
    private(set) var record: SyncRecord?
    private(set) var conflict: WorkoutEnvelope?
    private(set) var busy = false
    private(set) var message: String?
    var onChange: (() -> Void)?
    var dirty: Bool { record?.isDirty == true || record?.sent != nil }
    private var key: String? { account.map { api.origin.storageKey + "|" + $0.userId } }

    init(api: any WorkoutAPI, sessions: any SessionStoring, repository: WorkoutRepository) {
        self.api = api; self.sessions = sessions; self.repository = repository
    }

    func restore() async {
        guard !busy else { return }
        busy = true; onChange?()
        defer { busy = false; onChange?() }
        do {
            guard let token = try sessions.read() else { return }
            try await authenticate(token)
            try await refreshRecord()
        } catch { handle(error) }
    }

    func signIn(email: String, password: String) async {
        guard !busy else { return }
        busy = true; message = nil; onChange?()
        defer { busy = false; onChange?() }
        do {
            let token = try await api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            do { try await authenticate(token) }
            catch { try? await api.signOut(token: token); throw error }
            try await refreshRecord()
        } catch { handle(error) }
    }

    private func authenticate(_ token: String) async throws {
        let account = try await api.account(token: token)
        guard !account.needsPassword else { throw APIError.forbidden }
        let cached = try repository.read(key: api.origin.storageKey + "|" + account.userId)
        try sessions.write(token)
        self.token = token; self.account = account
        record = cached; conflict = nil
    }

    func changeRampSets(_ value: Int) {
        guard !busy, [1, 2].contains(value), var next = record, next.sent == nil, let key else { return }
        next.local.rampSets = value
        do {
            try repository.write(next, key: key)
            record = next; message = "Saved on this iPhone. Sync to update your other devices."
        } catch { handle(error) }
        onChange?()
    }

    func refresh() async {
        guard !busy else { return }
        busy = true; message = nil; onChange?()
        defer { busy = false; onChange?() }
        do { try await refreshRecord() } catch { handle(error) }
    }

    private func refreshRecord() async throws {
        guard let account, let token, let key else { throw APIError.unauthorized }
        let remote = try await api.load(profile: account.profile, token: token)
        if let current = record, current.isDirty || current.sent != nil {
            if current.sent == remote.data {
                let recovered = SyncRecord(base: remote, local: current.local)
                try repository.write(recovered, key: key)
                record = recovered; conflict = nil
            } else if current.base != remote {
                conflict = remote
                throw APIError.conflict
            }
        } else {
            let next = SyncRecord(base: remote, local: remote.data)
            try repository.write(next, key: key)
            record = next; conflict = nil
        }
        message = dirty ? "Changes on this iPhone are waiting to sync." : "Synced securely."
    }

    func sync() async {
        guard !busy else { return }
        busy = true; message = nil; onChange?()
        defer { busy = false; onChange?() }
        do {
            // Reconcile uncertain responses before attempting another revisioned write.
            try await refreshRecord()
            guard conflict == nil, var next = record, next.isDirty,
                  let token, let account, let key else { return }
            next.sent = next.local
            try repository.write(next, key: key)
            record = next
            let revision = try await api.save(profile: account.profile, data: next.local,
                revision: next.base.revision, token: token)
            next.base = WorkoutEnvelope(data: next.local, revision: revision)
            next.sent = nil
            try repository.write(next, key: key)
            record = next; message = "Synced securely."
        } catch {
            if error as? APIError == .conflict {
                try? await refreshRecord()
            }
            handle(error)
        }
    }

    // The milestone allows discarding a pending preference, never an automatic overwrite.
    func useCloudCopy() {
        guard !busy, let remote = conflict, let key else { return }
        let next = SyncRecord(base: remote, local: remote.data)
        do {
            try repository.write(next, key: key)
            record = next; conflict = nil; message = "Using the cloud copy."
        } catch { handle(error) }
        onChange?()
    }

    func signOut(localOnly: Bool = false) async {
        guard !busy else { return }
        busy = true; onChange?()
        defer { busy = false; onChange?() }
        do {
            if !localOnly, let token {
                do { try await api.signOut(token: token) }
                catch APIError.unauthorized { /* Already revoked. */ }
            }
            if let key { try repository.remove(key: key) }
            try sessions.remove()
            token = nil; account = nil; record = nil; conflict = nil
            message = localOnly ? "Signed out on this iPhone. The server session could not be revoked." : nil
        } catch { handle(error) }
    }

    private func handle(_ error: any Error) {
        if error as? APIError == .unauthorized {
            token = nil; account = nil; record = nil; conflict = nil
            do { try sessions.remove() }
            catch { message = error.localizedDescription; return }
        }
        message = (error as? LocalizedError)?.errorDescription ?? "Could not complete that action. Please retry."
    }
}
