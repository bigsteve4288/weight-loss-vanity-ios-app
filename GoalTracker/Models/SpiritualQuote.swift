import Foundation
import SwiftData

@Model
final class SpiritualQuote {
    var text: String
    var source: String
    var isFavorite: Bool
    var createdAt: Date

    init(text: String, source: String, isFavorite: Bool = false, createdAt: Date = .now) {
        self.text = text
        self.source = source
        self.isFavorite = isFavorite
        self.createdAt = createdAt
    }
}
