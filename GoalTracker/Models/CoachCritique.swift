import Foundation
import SwiftData

/// A saved AI Coach verdict on a THEN/NOW photo pair.
@Model
final class CoachCritique {
    var date: Date
    var toneRaw: String
    var grade: String
    var headline: String
    var observations: [String]
    var progressSinceThen: String
    var focusAreas: [String]
    var ordersForToday: [String]

    init(date: Date = .now, tone: CoachTone, verdict: CoachVerdict) {
        self.date = date
        self.toneRaw = tone.rawValue
        self.grade = verdict.grade
        self.headline = verdict.headline
        self.observations = verdict.observations
        self.progressSinceThen = verdict.progressSinceThen
        self.focusAreas = verdict.focusAreas
        self.ordersForToday = verdict.ordersForToday
    }

    var tone: CoachTone { CoachTone(rawValue: toneRaw) ?? .blunt }
}
