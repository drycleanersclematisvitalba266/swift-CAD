import Foundation
import CADCore

public struct DocumentMetadata: Codable, Sendable {
    public var name: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String? = nil) {
        let now = Date()
        self.init(name: name, createdAt: now, updatedAt: now)
    }

    public init(name: String? = nil, createdAt: Date, updatedAt: Date) {
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func validate() throws {
        let created = createdAt.timeIntervalSinceReferenceDate
        let updated = updatedAt.timeIntervalSinceReferenceDate
        guard created.isFinite, updated.isFinite else {
            throw SchemaError.invalidMetadata("Document metadata timestamps must be finite.")
        }
        guard updatedAt >= createdAt else {
            throw SchemaError.invalidMetadata("Document metadata updatedAt must not be earlier than createdAt.")
        }
    }
}
