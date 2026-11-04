import Foundation
import SwiftData

enum SeedData {
    static let quotes: [(text: String, source: String)] = [
        ("I can do all things through Christ which strengtheneth me.", "Philippians 4:13"),
        ("Be strong and of a good courage; be not afraid, neither be thou dismayed: for the LORD thy God is with thee whithersoever thou goest.", "Joshua 1:9"),
        ("For God hath not given us the spirit of fear; but of power, and of love, and of a sound mind.", "2 Timothy 1:7"),
        ("Know ye not that your body is the temple of the Holy Ghost which is in you?", "1 Corinthians 6:19"),
        ("They that wait upon the LORD shall renew their strength; they shall run, and not be weary; and they shall walk, and not faint.", "Isaiah 40:31"),
        ("And let us not be weary in well doing: for in due season we shall reap, if we faint not.", "Galatians 6:9"),
        ("Discipline is choosing between what you want now and what you want most.", "Unknown"),
        ("The craving will pass. The goal remains.", "GoalTracker"),
    ]

    @MainActor
    static func insertDefaultQuotesIfNeeded(into context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<SpiritualQuote>())) ?? 0
        guard count == 0 else { return }
        for (index, quote) in quotes.enumerated() {
            // Stagger timestamps so the seeded order is preserved when sorted by date.
            context.insert(SpiritualQuote(text: quote.text, source: quote.source, createdAt: Date(timeIntervalSinceNow: -Double(index))))
        }
    }
}
