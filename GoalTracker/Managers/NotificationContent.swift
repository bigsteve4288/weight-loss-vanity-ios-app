import Foundation

/// Built-in check-in text, used whenever the coach hasn't written a message for that slot
/// (no access code, offline, or further ahead than the coach writes).
enum NotificationContent {
    static func prompts(for slot: ReminderSlot, skipsBreakfast: Bool) -> [String] {
        switch slot {
        case .wake:
            ["Feet on the floor. Move before you can talk yourself out of it.",
             "Workout first, excuses never. Lace up.",
             "Step on the scale, face the number, own the day."]
        case .beforeBreakfast where skipsBreakfast:
            ["You're in your fasting window. Water, black coffee, hold the line.",
             "Hunger this morning is a signal, not an emergency. Drink water and keep going.",
             "Every hour you hold the fast is a vote for the person you're becoming."]
        case .beforeBreakfast:
            ["Protein first. Plan today's meals before you're hungry.",
             "Log breakfast before you eat it.",
             "Water first, then decide what goes on the plate."]
        case .midMorning:
            ["Hunger is a wave. Ride it out with a glass of water.",
             "No grazing. Your next meal is coming.",
             "That snack won't fix the morning. Lunch is a few hours away."]
        case .beforeLunch:
            ["Decide before you order: protein, vegetables, a sensible portion.",
             "Lunch is fuel, not a reward. Choose like your goal depends on it.",
             "Log lunch before the first bite."]
        case .afternoon:
            ["Beat the afternoon slump with water and a walk, not the vending machine.",
             "Plan dinner now so you're not winging it tonight.",
             "Halfway through the day. Don't give it back now."]
        case .evening:
            ["Kitchen's closed. Brush your teeth and call it a day.",
             "Win tonight and tomorrow starts easy.",
             "Lay out tomorrow's workout clothes and get to bed on time."]
        }
    }

    static func body(slot: ReminderSlot, skipsBreakfast: Bool, quote: (text: String, source: String)?, index: Int) -> String {
        let options = prompts(for: slot, skipsBreakfast: skipsBreakfast)
        let prompt = options[index % options.count]
        guard let quote, index.isMultiple(of: 2) else { return prompt }
        return "\(prompt)\n\u{201C}\(quote.text)\u{201D} \u{2014} \(quote.source)"
    }

    /// Live numbers shown under every check-in, filled in when the app reschedules.
    static func countdown(daysLeft: Int, poundsLeft: Double?) -> String {
        let days = daysLeft == 1 ? "1 day" : "\(daysLeft) days"
        guard let poundsLeft else { return days }
        return poundsLeft <= 0 ? "\(days) · goal weight reached" : "\(days) · \(String(format: "%.1f", poundsLeft)) lb to go"
    }
}
