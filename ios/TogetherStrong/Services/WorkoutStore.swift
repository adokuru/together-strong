import Foundation

@MainActor
final class WorkoutStore {
    let api: any WorkoutAPI
    private let sessions: any SessionStoring
    private let repository: WorkoutRepository
    private var token: String?
    private let restAlerts: any RestAlertScheduling
    private(set) var account: Account?
    private(set) var record: SyncRecord?
    private(set) var conflict: WorkoutEnvelope?
    private(set) var busy = false
    private(set) var message: String?
    var onChange: (() -> Void)?
    private var observers: [UUID: () -> Void] = [:]
    private var scheduledSync: Task<Void, Never>?
    private let automaticSync: Bool
    private var signingOut = false
    var canEdit: Bool { account != nil && record != nil && !signingOut }
    func observe(_ callback: @escaping () -> Void) -> UUID {
        let id = UUID(); observers[id] = callback; return id
    }
    func removeObserver(_ id: UUID) { observers[id] = nil }
    private func notify() { onChange?(); for callback in Array(observers.values) { callback() } }
    var dirty: Bool { record?.isDirty == true || record?.sent != nil }
    private var key: String? { account.map { api.origin.storageKey + "|" + $0.userId } }

    init(api: any WorkoutAPI, sessions: any SessionStoring, repository: WorkoutRepository, automaticSync: Bool = true, restAlerts: (any RestAlertScheduling)? = nil) {
        self.api = api; self.sessions = sessions; self.repository = repository; self.automaticSync = automaticSync
        self.restAlerts = restAlerts ?? LocalRestAlerts()
    }

    func restore() async {
        guard !busy else { return }
        busy = true; notify()
        defer { busy = false; notify() }
        do {
            guard let token = try sessions.read() else { return }
            try await authenticate(token)
            try await refreshRecord()
        } catch { handle(error) }
    }

    func signIn(email: String, password: String) async {
        guard !busy else { return }
        busy = true; message = nil; notify()
        defer { busy = false; notify() }
        do {
            let token = try await api.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            do { try await authenticate(token) }
            catch { try? await api.signOut(token: token); throw error }
            try await refreshRecord()
        } catch { handle(error) }
    }

    private func authenticate(_ token: String) async throws {
        scheduledSync?.cancel()
        let account = try await api.account(token: token)
        guard !account.needsPassword else { throw APIError.forbidden }
        let cached = try repository.read(key: api.origin.storageKey + "|" + account.userId)
        try sessions.write(token)
        self.token = token; self.account = account
        record = cached; conflict = nil
        if let cached { try persist(cached) }
        reconcileRestAlert()
    }

    @discardableResult
    func edit(autosync: Bool = true, _ transform: (inout WorkoutDocument) throws -> Void) -> Bool {
        guard var next = record, canEdit else { return false }
        do {
            try transform(&next.local)
            try persist(next)
            message = "Saved on this iPhone."
            if autosync { scheduleSync() }
            notify(); return true
        } catch { handle(error); notify(); return false }
    }

    func changeRampSets(_ value: Int) {
        guard [1, 2].contains(value) else { return }
        edit(autosync: false) { $0.rampSets = value }
    }

    func scheduleSync() {
        guard automaticSync, canEdit, conflict == nil else { return }
        scheduledSync?.cancel()
        scheduledSync = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            guard let self else { return }
            self.scheduledSync = nil
            guard self.canEdit, !self.busy else { return }
            await self.sync()
        }
    }

    func refresh() async {
        guard !busy else { return }
        busy = true; message = nil; notify()
        defer { busy = false; notify() }
        do { try await refreshRecord() } catch { handle(error) }
    }

    private func refreshRecord() async throws {
        guard let account, let token, key != nil else { throw APIError.unauthorized }
        let remote = try await api.load(profile: account.profile, token: token)
        if let current = record, current.isDirty || current.sent != nil {
            if current.sent == remote.data {
                let recovered = SyncRecord(base: remote, local: current.local, recoveryCopy: current.recoveryCopy, restTimer: current.restTimer, restAlertsEnabled: current.restAlertsEnabled)
                try persist(recovered)
                conflict = nil
            } else if current.base != remote {
                conflict = remote
                throw APIError.conflict
            }
        } else {
            let next = SyncRecord(base: remote, local: remote.data, recoveryCopy: record?.recoveryCopy, restTimer: record?.restTimer, restAlertsEnabled: record?.restAlertsEnabled)
            try persist(next)
            conflict = nil
        }
        message = dirty ? "Changes on this iPhone are waiting to sync." : "Synced securely."
    }

    func sync() async {
        guard !busy else { return }
        busy = true; message = nil; notify()
        defer { busy = false; notify() }
        do {
            // Reconcile uncertain responses before attempting another revisioned write.
            try await refreshRecord()
            guard conflict == nil, var next = record, (next.isDirty || next.sent != nil),
                  let token, let account, let key else { return }
            next.sent = next.local
            try repository.write(next, key: key)
            record = next
            let revision = try await api.save(profile: account.profile, data: next.local,
                revision: next.base.revision, token: token)
            guard var latest = record else { return }
            latest.base = WorkoutEnvelope(data: next.local, revision: revision)
            latest.sent = nil
            try persist(latest)
            message = dirty ? "Your newest changes are waiting to sync." : "Synced securely."
            if dirty { scheduleSync() }
        } catch {
            if error as? APIError == .conflict {
                try? await refreshRecord()
            }
            handle(error)
        }
    }

    // A conflict choice retains a separate, account-scoped local recovery copy.
    func useCloudCopy() {
        guard !busy, let remote = conflict, key != nil else { return }
        guard record?.recoveryCopy == nil else {
            message = "A previous recovery copy is still saved. Review it before replacing another local copy."
            notify(); return
        }
        let next = SyncRecord(base: remote, local: remote.data, recoveryCopy: record?.local, restTimer: record?.restTimer, restAlertsEnabled: record?.restAlertsEnabled)
        do {
            try persist(next)
            conflict = nil; message = "Using the cloud copy."
        } catch { handle(error) }
        notify()
    }

    func signOut(localOnly: Bool = false) async {
        guard !busy else { return }
        busy = true; signingOut = true; scheduledSync?.cancel(); notify()
        defer { busy = false; signingOut = false; notify() }
        do {
            if !localOnly, let token {
                do { try await api.signOut(token: token) }
                catch APIError.unauthorized { /* Already revoked. */ }
            }
            if let key { try repository.remove(key: key) }
            try sessions.remove()
            token = nil; account = nil; record = nil; conflict = nil
            restAlerts.update(deadline: nil, enabled: false)
            message = localOnly ? "Signed out on this iPhone. The server session could not be revoked." : nil
        } catch { handle(error) }
    }

    @discardableResult
    func removeRecoveryCopy() -> Bool {
        guard !busy, var next = record, let key else { return false }
        next.recoveryCopy = nil
        do {
            try repository.write(next, key: key); record = next; message = "Local recovery copy removed."
            notify(); return true
        } catch { handle(error); notify(); return false }
    }

    private func persist(_ value: SyncRecord) throws {
        guard let key else { throw APIError.unauthorized }
        var value = value
        if let timer = value.restTimer {
            let session = value.local.session(timer.sessionID)
            if session == nil || session?.discarded == true || session?.isCompleted == true || session?.isPaused == true {
                value.restTimer = nil
            }
        }
        let changed = value.restTimer != record?.restTimer || value.restAlertsEnabled != record?.restAlertsEnabled
        try repository.write(value, key: key)
        record = value
        if changed { reconcileRestAlert() }
    }

    private func reconcileRestAlert() {
        restAlerts.update(deadline: record?.restTimer?.deadline, enabled: record?.restAlertsEnabled == true)
    }

    @discardableResult
    func startRest(sessionID: String, exercise: Exercise, now: Date = Date()) -> Bool {
        guard canEdit, var next = record, let session = next.local.session(sessionID),
              !session.isCompleted, !session.discarded, !session.isPaused, !session.sets(exercise.id).isEmpty else { return false }
        next.restTimer = RestTimerState(sessionID: sessionID, exerciseID: exercise.id, duration: exercise.rest, now: now)
        return saveTimer(next)
    }

    @discardableResult
    func changeRest(_ action: (inout RestTimerState) -> Void) -> Bool {
        guard canEdit, var next = record, var timer = next.restTimer else { return false }
        action(&timer); next.restTimer = timer
        return saveTimer(next)
    }

    @discardableResult
    func endRest() -> Bool {
        guard var next = record, canEdit else { return false }
        next.restTimer = nil
        return saveTimer(next)
    }

    private func saveTimer(_ next: SyncRecord) -> Bool {
        do { try persist(next); notify(); return true }
        catch { handle(error); notify(); return false }
    }

    func enableRestAlerts() async -> Bool {
        guard let identity = key, canEdit else { return false }
        do {
            let granted = try await restAlerts.requestPermission()
            guard key == identity, canEdit, var next = record else { return false }
            next.restAlertsEnabled = granted
            guard saveTimer(next) else { return false }
            reconcileRestAlert()
            return granted
        } catch { message = "Rest alerts could not be enabled. The timer still works."; notify(); return false }
    }

    @discardableResult
    func disableRestAlerts() -> Bool {
        guard var next = record, canEdit else { return false }
        next.restAlertsEnabled = false; return saveTimer(next)
    }

    private func handle(_ error: any Error) {
        if error as? APIError == .unauthorized {
            scheduledSync?.cancel()
            token = nil; account = nil; record = nil; conflict = nil
            restAlerts.update(deadline: nil, enabled: false)
            do { try sessions.remove() }
            catch { message = error.localizedDescription; return }
        }
        message = (error as? LocalizedError)?.errorDescription ?? "Could not complete that action. Please retry."
    }
}
