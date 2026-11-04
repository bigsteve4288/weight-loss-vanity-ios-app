import Foundation
import SwiftData

extension [ProgressPhoto] {
    /// The chosen THEN photo, falling back to the baseline. Expects photos sorted oldest first.
    func thenPhoto(selected id: PersistentIdentifier?) -> ProgressPhoto? {
        first { $0.persistentModelID == id } ?? first(where: \.isBaseline)
    }

    /// The chosen NOW photo, falling back to the newest non-baseline photo. Expects photos sorted oldest first.
    func nowPhoto(selected id: PersistentIdentifier?) -> ProgressPhoto? {
        first { $0.persistentModelID == id } ?? last { !$0.isBaseline }
    }
}

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
