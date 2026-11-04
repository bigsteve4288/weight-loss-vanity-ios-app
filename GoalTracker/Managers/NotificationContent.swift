import Foundation

/// Builds the rotating text for daily accountability notifications.
enum NotificationContent {
    static let prompts = [
        "Step on the scale. Face the number. Own the day.",
        "Plan every meal before you're hungry.",
        "Close your rings. Earn your deficit.",
        "Cravings are temporary. Your birthday photo is forever.",
        "Log every bite in Carb Manager today.",
        "Drink water first. Decide later.",
        "Pray before you plate.",
    ]

    static func title(daysLeft: Int, poundsLeft: Double?, index: Int) -> String {
        let pounds = poundsLeft.map { String(format: "%.1f", $0) }
        let options = [
            pounds.map { "\(daysLeft) days. \($0) lbs. No excuses." } ?? "\(daysLeft) days. No excuses.",
            "\(daysLeft) days until your birthday goal",
            "Remember why you started",
            "Win the morning. Win the day.",
        ]
        return options[index % options.count]
    }

    static func body(quote: (text: String, source: String)?, index: Int) -> String {
        let prompt = prompts[index % prompts.count]
        guard let quote else { return prompt }
        return "\u{201C}\(quote.text)\u{201D} \u{2014} \(quote.source)\n\(prompt)"
    }

    /// The next `hour:minute` at or after `now`, shifted by `dayOffset` days.
    static func fireDate(dayOffset: Int, hour: Int, minute: Int, now: Date = .now, calendar: Calendar = .current) -> Date? {
        guard let today = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
        let first = today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)
        return first.flatMap { calendar.date(byAdding: .day, value: dayOffset, to: $0) }
    }
}
