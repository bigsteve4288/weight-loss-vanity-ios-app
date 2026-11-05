import Foundation
import SwiftData

/// One turn of the Ask the Coach conversation. Stored on this device only.
@Model
final class CoachMessage {
    var date: Date
    /// "user" or "assistant", matching the Messages API roles.
    var roleRaw: String
    var text: String

    init(date: Date = .now, role: Role, text: String) {
        self.date = date
        self.roleRaw = role.rawValue
        self.text = text
    }

    enum Role: String, Sendable {
        case user, assistant
    }

    var role: Role { Role(rawValue: roleRaw) ?? .user }
}
