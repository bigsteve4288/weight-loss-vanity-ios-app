import Foundation
import Observation
import UserNotifications

/// Schedules daily lock-screen accountability notifications with the baseline photo attached.
/// iOS repeating triggers can't change their content, so the next two weeks are scheduled as
/// individual notifications and rebuilt every time the app becomes active.
@MainActor
@Observable
final class UserNotificationManager {
    private(set) var isAuthorized = false
    private(set) var scheduledCount = 0
    private(set) var isDenied = false
    private(set) var testStatus: String?

    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    static let daysAhead = 14
    private static let dailyPrefix = "goaltracker.daily."

    func refreshAuthorizationStatus() async {
        let status = await center.notificationSettings().authorizationStatus
        isAuthorized = status == .authorized || status == .provisional
        isDenied = status == .denied
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        isAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        return isAuthorized
    }

    func reschedule(profile: GoalProfile?, currentWeight: Double?, quotes: [SpiritualQuote], baselineImageData: Data?) async {
        center.removePendingNotificationRequests(withIdentifiers: (0..<Self.daysAhead).map { Self.dailyPrefix + "\($0)" })
        scheduledCount = 0
        guard let profile, profile.notificationsEnabled else { return }
        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        let calendar = Calendar.current
        let quoteList = quotes.map { (text: $0.text, source: $0.source) }
        let image = baselineImageData.flatMap { ImageProcessing.downscaledJPEG($0, maxDimension: 800) }
        let poundsLeft = currentWeight.map { max($0 - profile.targetWeightLbs, 0) }

        for offset in 0..<Self.daysAhead {
            guard let fireDate = NotificationContent.fireDate(
                dayOffset: offset, hour: profile.notificationHour, minute: profile.notificationMinute, calendar: calendar
            ) else { continue }

            let daysLeft = TargetEngine.daysRemaining(from: fireDate, to: profile.targetDate, calendar: calendar)
            guard daysLeft >= 0 else { break }

            let dayIndex = calendar.ordinality(of: .day, in: .era, for: fireDate) ?? offset
            let content = makeContent(daysLeft: daysLeft, poundsLeft: poundsLeft, index: dayIndex, quotes: quoteList, image: image)
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: Self.dailyPrefix + "\(offset)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            if (try? await center.add(request)) != nil {
                scheduledCount += 1
            }
        }
    }

    func sendTestNotification(profile: GoalProfile, currentWeight: Double?, quotes: [SpiritualQuote], baselineImageData: Data?) async {
        guard await requestAuthorization() else {
            testStatus = "Notifications are turned off for GoalTracker. Turn them on in Settings to receive them."
            return
        }
        let content = makeContent(
            daysLeft: TargetEngine.daysRemaining(from: .now, to: profile.targetDate),
            poundsLeft: currentWeight.map { max($0 - profile.targetWeightLbs, 0) },
            index: Int.random(in: 0..<100),
            quotes: quotes.map { (text: $0.text, source: $0.source) },
            image: baselineImageData.flatMap { ImageProcessing.downscaledJPEG($0, maxDimension: 800) }
        )
        let request = UNNotificationRequest(
            identifier: "goaltracker.test",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        )
        do {
            try await center.add(request)
            testStatus = "Test sent. It arrives in 5 seconds; lock your phone to see it on the Lock Screen."
        } catch {
            testStatus = "Couldn't schedule the test: \(error.localizedDescription)"
        }
    }

    private func makeContent(
        daysLeft: Int,
        poundsLeft: Double?,
        index: Int,
        quotes: [(text: String, source: String)],
        image: Data?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = NotificationContent.title(daysLeft: daysLeft, poundsLeft: poundsLeft, index: index)
        content.body = NotificationContent.body(quote: quotes.isEmpty ? nil : quotes[index % quotes.count], index: index)
        content.sound = .default
        if let image, let attachment = Self.attachment(for: image) {
            content.attachments = [attachment]
        }
        return content
    }

    /// Each attachment needs its own file; the system moves it into its store when the request is added.
    private static func attachment(for data: Data) -> UNNotificationAttachment? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("baseline-\(UUID().uuidString).jpg")
        do {
            try data.write(to: url)
            return try UNNotificationAttachment(identifier: "baseline", url: url)
        } catch {
            return nil
        }
    }
}
