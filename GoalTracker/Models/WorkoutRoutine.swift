import Foundation
import SwiftData

@Model
final class WorkoutRoutine {
    var name: String
    var focus: String
    var durationMinutes: Int
    /// Calendar weekday numbers, 1 = Sunday … 7 = Saturday.
    var weekdays: [Int]
    var notes: String
    var createdAt: Date

    init(name: String, focus: String = "", durationMinutes: Int = 45, weekdays: [Int] = [], notes: String = "", createdAt: Date = .now) {
        self.name = name
        self.focus = focus
        self.durationMinutes = durationMinutes
        self.weekdays = weekdays
        self.notes = notes
        self.createdAt = createdAt
    }
}
