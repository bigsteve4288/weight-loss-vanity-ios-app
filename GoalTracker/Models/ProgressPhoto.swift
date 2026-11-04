import Foundation
import SwiftData

@Model
final class ProgressPhoto {
    var date: Date
    @Attribute(.externalStorage) var imageData: Data
    /// The "Then" anchor photo. At most one photo should be the baseline.
    var isBaseline: Bool
    var weightLbs: Double?

    init(date: Date = .now, imageData: Data, isBaseline: Bool, weightLbs: Double? = nil) {
        self.date = date
        self.imageData = imageData
        self.isBaseline = isBaseline
        self.weightLbs = weightLbs
    }
}
