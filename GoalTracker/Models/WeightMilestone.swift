import Foundation
import SwiftData

@Model
final class WeightMilestone {
    var title: String
    var targetWeightLbs: Double
    var achievedDate: Date?
    var createdAt: Date

    init(title: String, targetWeightLbs: Double, achievedDate: Date? = nil, createdAt: Date = .now) {
        self.title = title
        self.targetWeightLbs = targetWeightLbs
        self.achievedDate = achievedDate
        self.createdAt = createdAt
    }
}
