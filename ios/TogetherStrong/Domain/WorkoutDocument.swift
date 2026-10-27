import Foundation

enum Profile: String, Codable, CaseIterable {
    case david = "David"
    case mary = "Mary"
}

enum JSONValue: Codable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
}

// Preserve the complete server document, including fields this milestone does not edit.
struct WorkoutDocument: Codable, Equatable {
    private var fields: [String: JSONValue]

    init(from decoder: any Decoder) throws {
        let fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
        guard fields["version"] == .number(1),
              fields["rampSets"] == .number(1) || fields["rampSets"] == .number(2),
              let sessions = fields["sessions"]?.array, sessions.count <= 1_000 else {
            throw APIError.invalidDocument
        }
        self.fields = fields
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }

    var rampSets: Int {
        get { fields["rampSets"] == .number(1) ? 1 : 2 }
        set { fields["rampSets"] = .number(Double(newValue)) }
    }
    var sessionCount: Int { fields["sessions"]?.array?.count ?? 0 }
    var completedSessionCount: Int {
        (fields["sessions"]?.array ?? []).filter { session in
            guard let value = session.object, case .string = value["completedAt"],
                  value["discardedAt"] == nil || value["discardedAt"] == .null else { return false }
            return value["sets"]?.object?.values.contains { sets in
                sets.array?.contains { $0.object?["done"] == .bool(true) } ?? false
            } ?? false
        }.count
    }
}

struct WorkoutEnvelope: Codable, Equatable {
    var data: WorkoutDocument
    var revision: Int
}

struct Account: Codable, Equatable {
    let userId: String
    let profile: Profile
    let needsPassword: Bool
}

struct SyncRecord: Codable, Equatable {
    var base: WorkoutEnvelope
    var local: WorkoutDocument
    var sent: WorkoutDocument?
    var isDirty: Bool { local != base.data }
}
