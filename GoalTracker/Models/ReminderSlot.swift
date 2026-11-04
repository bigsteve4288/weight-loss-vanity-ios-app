import Foundation

/// The six moments in the day when the coach checks in. Times are derived from the user's day
/// (wake, meals, bed) so they fit whenever that person actually eats.
enum ReminderSlot: String, CaseIterable, Identifiable, Codable, Sendable {
    case wake
    case beforeBreakfast
    case midMorning
    case beforeLunch
    case afternoon
    case evening

    var id: Self { self }

    var label: String {
        switch self {
        case .wake: "Wake-up & Workout"
        case .beforeBreakfast: "Before Breakfast"
        case .midMorning: "No-Snack Check"
        case .beforeLunch: "Before Lunch"
        case .afternoon: "Afternoon"
        case .evening: "Finish the Night"
        }
    }

    var systemImage: String {
        switch self {
        case .wake: "alarm.fill"
        case .beforeBreakfast: "sunrise.fill"
        case .midMorning: "hand.raised.fill"
        case .beforeLunch: "fork.knife"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        }
    }

    /// What this check-in is for, given to the coach when it writes the message.
    func purpose(skipsBreakfast: Bool) -> String {
        switch self {
        case .wake:
            "They just woke up. Get them out of bed and moving: a workout, a walk, or at least the scale. Set the tone for the day."
        case .beforeBreakfast:
            skipsBreakfast
                ? "They skip breakfast and are in a morning fasting window. Help them hold it: water, black coffee, purpose behind the fast."
                : "Breakfast is coming. Push protein first, a plan for the day, and logging the meal."
        case .midMorning:
            "Between breakfast and lunch, when snacking creeps in. Hold the line: no grazing, drink water, hunger passes."
        case .beforeLunch:
            "Lunch is about to happen. Make the right choice before ordering or plating: protein, vegetables, a sensible portion, log it."
        case .afternoon:
            "After lunch, before dinner: the afternoon slump and the drive home. Avoid the vending machine and plan a dinner that fits the deficit."
        case .evening:
            "Dinner is done. Close the kitchen, no late-night eating, reflect on the day, set up tomorrow and get to bed on time."
        }
    }

    /// The time this slot fires, before any override: minutes after midnight.
    func derivedMinutes(for day: DailyRhythm) -> Int {
        switch self {
        case .wake:
            return day.wake
        case .beforeBreakfast:
            return day.breakfast.map { max($0 - 15, day.wake + 5) } ?? day.wake + 90
        case .midMorning:
            return ((day.breakfast ?? day.wake) + day.lunch) / 2
        case .beforeLunch:
            return day.lunch - 15
        case .afternoon:
            return (day.lunch + day.dinner) / 2
        case .evening:
            // A bedtime after midnight still means tonight.
            let bed = day.bed < day.wake ? day.bed + 1440 : day.bed
            return min(max(bed - 90, day.dinner + 30), 1439)
        }
    }

    /// Minutes after midnight this slot fires, or `nil` if the user turned it off.
    func minutes(for profile: GoalProfile) -> Int? {
        guard let override = profile.reminderOverrides[rawValue] else { return derivedMinutes(for: profile.dailyRhythm) }
        return override < 0 ? nil : override
    }

    static func enabled(for profile: GoalProfile) -> [(slot: ReminderSlot, minutes: Int)] {
        allCases.compactMap { slot in slot.minutes(for: profile).map { (slot, $0) } }
    }
}

/// When the user wakes, eats and sleeps, in minutes after midnight.
struct DailyRhythm: Equatable, Sendable {
    var wake: Int
    /// `nil` when they skip breakfast.
    var breakfast: Int?
    var lunch: Int
    var dinner: Int
    var bed: Int

    /// Meals must fall in order through the day; bedtime may be after midnight.
    var isInOrder: Bool {
        wake < (breakfast ?? wake + 1) && (breakfast ?? wake) < lunch && lunch < dinner
    }
}

extension GoalProfile {
    var dailyRhythm: DailyRhythm {
        get { DailyRhythm(wake: wakeMinutes, breakfast: breakfastMinutes, lunch: lunchMinutes, dinner: dinnerMinutes, bed: bedMinutes) }
        set {
            wakeMinutes = newValue.wake
            breakfastMinutes = newValue.breakfast
            lunchMinutes = newValue.lunch
            dinnerMinutes = newValue.dinner
            bedMinutes = newValue.bed
        }
    }
}

extension Int {
    /// Minutes after midnight as a `Date` on `day`, for pickers and triggers.
    func asTime(on day: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: self / 60, minute: self % 60, second: 0, of: day) ?? day
    }
}

extension Date {
    var minutesAfterMidnight: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
