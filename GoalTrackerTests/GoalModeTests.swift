import Foundation
import SwiftData
import Testing
@testable import GoalTracker

struct AggressiveModeEngineTests {
    private let now = Fixture.date(2026, 11, 5, hour: 9)
    private let deadline = Fixture.date(2026, 12, 14)

    private func input(_ intensity: GoalIntensity, clinicianPace: Double? = nil) -> TargetEngine.Input {
        TargetEngine.Input(
            startWeight: 334.7, lossGoal: 34, targetDate: deadline, currentWeight: 330, latestWeightDate: now,
            history: [], nutrition: Fixture.log(calories: 190, protein: 7, entries: [now.addingTimeInterval(-1800)]),
            activeBurn: 80, basalBurn: 700, restingCaloriesPerDay: 2200, rhythm: Fixture.rhythm,
            intensity: intensity, clinicianMaxPoundsPerWeek: clinicianPace, now: now, calendar: Fixture.calendar
        )
    }

    @Test func aggressiveKeepsTheExactGoalAndDeadline() {
        let snapshot = TargetEngine.snapshot(input(.aggressive))
        #expect(abs(snapshot.plan.targetWeight - 300.7) < 1e-9)
        #expect(snapshot.plan.targetDate == deadline)
        #expect(abs(snapshot.pace.requiredPoundsPerWeek - 29.3 / 39 * 7) < 1e-9)
        #expect(!snapshot.plan.needsAdjustment)
        #expect(snapshot.plan.risk == .severe)
        // A safer date is offered, not applied.
        #expect(snapshot.plan.suggestedTargetDate != nil)
    }

    @Test func dailyVerdictIsSeparateFromTrajectory() {
        #expect(TargetEngine.snapshot(input(.standard)).status == .goalNeedsAdjustment)
        let aggressive = TargetEngine.snapshot(input(.aggressive))
        #expect(aggressive.status != .goalNeedsAdjustment)
        #expect(aggressive.status == .buildingMomentum)
        #expect(aggressive.pace.status == .insufficientData)
    }

    @Test(arguments: GoalIntensity.allCases)
    func noModeGeneratesAnUnsafeCalorieRecommendation(intensity: GoalIntensity) {
        for clinicianPace in [nil, 3.0, 6.0] {
            let snapshot = TargetEngine.snapshot(input(intensity, clinicianPace: clinicianPace))
            #expect(snapshot.plan.recommendedDailyDeficitEstimate <= PacePolicy.standard.maximumDailyDeficit)
            #expect(!snapshot.status.message.localizedCaseInsensitiveContains("tighten"))
            #expect(!snapshot.status.message.localizedCaseInsensitiveContains("add a workout"))
        }
    }

    @Test func clinicianPaceIsUsedOnlyWhenEnteredInClinicianMode() {
        let guided = TargetEngine.snapshot(input(.clinicianGuided, clinicianPace: 3))
        #expect(guided.plan.usesClinicianPace)
        #expect(guided.plan.sustainablePace.upperBound == 3)
        #expect(guided.plan.deficitCappedByApp)

        let noValue = TargetEngine.snapshot(input(.clinicianGuided))
        #expect(!noValue.plan.usesClinicianPace)
        #expect(noValue.plan.sustainablePace.upperBound == 2)

        let standard = TargetEngine.snapshot(input(.standard, clinicianPace: 3))
        #expect(!standard.plan.usesClinicianPace)
    }

    @Test func coachIsToldToRespectTheGoalWithoutPushingRestriction() {
        let lines = CoachViewModel.paceLines(TargetEngine.snapshot(input(.aggressive)), acknowledgedRequiredPace: 5.26).joined(separator: "\n")
        #expect(lines.contains("Goal mode: Aggressive"))
        #expect(lines.contains("Required pace for their deadline: 5.3 lb/week"))
        #expect(lines.contains("Never suggest closing the gap with more restriction or extra exercise"))
        #expect(lines.contains("Mention it at most once"))
        #expect(lines.contains("don't guess one"))
    }

    @Test func aRisingRequiredPaceSurfacesANewWarning() {
        let lines = CoachViewModel.paceLines(TargetEngine.snapshot(input(.aggressive)), acknowledgedRequiredPace: 3.0).joined(separator: "\n")
        #expect(lines.contains("risen meaningfully"))
    }
}

@MainActor
struct GoalPersistenceTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: GoalProfile.self, GoalChange.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func profile(in context: ModelContext) -> GoalProfile {
        let profile = GoalProfile(startWeightLbs: 334.7, lossGoalLbs: 34, targetDate: Fixture.date(2026, 12, 14))
        context.insert(profile)
        return profile
    }

    @Test func newProfilesDefaultToStandardWithNoHistory() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        #expect(profile.intensity == .standard)
        #expect(!profile.hasAcknowledgedAggressiveMode)
        #expect(profile.bariatricHistory == .notAnswered)
        #expect(!profile.shareHealthHistoryWithCoach)
        #expect(profile.effectiveClinicianMaxPoundsPerWeek == nil)
    }

    @Test func acknowledgmentPersistsAndStopsRepeating() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        GoalSettings.apply(intensity: .aggressive, clinicianMaxPace: nil, acknowledgedAggressive: true, requiredPace: 5.26, to: profile, context: context)
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<GoalProfile>()).first)
        #expect(fetched.intensity == .aggressive)
        #expect(fetched.aggressiveAcknowledgedVersion == AggressiveMode.acknowledgmentVersion)
        #expect(fetched.aggressiveAcknowledgedRequiredPace == 5.26)
        #expect(fetched.hasAcknowledgedAggressiveMode)
    }

    @Test func modeChangesPreserveTheGoalAndRecordHistory() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        GoalSettings.recordGoalChangeIfNeeded(profile, context: context)
        for mode in [GoalIntensity.aggressive, .standard, .clinicianGuided] {
            GoalSettings.apply(intensity: mode, clinicianMaxPace: 3, acknowledgedAggressive: true, requiredPace: nil, to: profile, context: context)
        }
        // Saving again without changes adds nothing.
        GoalSettings.apply(intensity: .clinicianGuided, clinicianMaxPace: 3, acknowledgedAggressive: false, requiredPace: nil, to: profile, context: context)

        #expect(profile.startWeightLbs == 334.7)
        #expect(profile.lossGoalLbs == 34)
        #expect(profile.targetDate == Fixture.date(2026, 12, 14))
        #expect(profile.effectiveClinicianMaxPoundsPerWeek == 3)
        let history = try context.fetch(FetchDescriptor<GoalChange>(sortBy: [SortDescriptor(\.date)]))
        #expect(history.map(\.intensity) == [.standard, .aggressive, .standard, .clinicianGuided])
        #expect(history.allSatisfy { abs($0.targetWeightLbs - 300.7) < 1e-9 })
    }

    @Test func forecastsDontOverwriteTheGoal() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        profile.intensity = .aggressive
        let health = HealthKitManager()
        _ = TargetEngine.snapshot(profile: profile, health: health, now: Fixture.date(2026, 11, 5))
        #expect(profile.targetWeightLbs == 300.7)
        #expect(profile.targetDate == Fixture.date(2026, 12, 14))
        #expect(try context.fetch(FetchDescriptor<GoalChange>()).isEmpty)
    }

    @Test func bariatricFieldsPersistAndAreOptional() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        profile.bariatricHistory = .yes
        profile.surgeryType = .sleeveGastrectomy
        profile.surgeryDate = Fixture.date(2019, 6, 1)
        profile.clinicianProteinGrams = 90
        profile.clinicianExerciseRestrictions = "No heavy lifting over 50 lb"
        profile.weightLossNotes = "Regained since 2022"
        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<GoalProfile>()).first)
        #expect(fetched.bariatricHistory == .yes)
        #expect(fetched.surgeryType == .sleeveGastrectomy)
        #expect(fetched.surgeryDate == Fixture.date(2019, 6, 1))
        #expect(fetched.clinicianProteinGrams == 90)
        #expect(fetched.weightLossNotes == "Regained since 2022")
    }

    @Test func aggressiveModeDoesntNeedSurgeryHistory() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        GoalSettings.apply(intensity: .aggressive, clinicianMaxPace: nil, acknowledgedAggressive: true, requiredPace: nil, to: profile, context: context)
        #expect(profile.intensity == .aggressive)
        #expect(profile.bariatricHistory == .notAnswered)
    }

    @Test func surgeryHistoryNeverChangesThePace() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        let health = HealthKitManager()
        let before = TargetEngine.snapshot(profile: profile, health: health, now: Fixture.date(2026, 11, 5)).plan
        profile.bariatricHistory = .yes
        profile.surgeryType = .sleeveGastrectomy
        let after = TargetEngine.snapshot(profile: profile, health: health, now: Fixture.date(2026, 11, 5)).plan
        #expect(before.sustainablePace == after.sustainablePace)
        #expect(before.recommendedPoundsPerWeek == after.recommendedPoundsPerWeek)
    }

    @Test func coachRequestsRespectConsentAndNeverReachNotifications() throws {
        let context = try makeContext()
        let profile = profile(in: context)
        profile.bariatricHistory = .yes
        profile.surgeryType = .sleeveGastrectomy
        let health = HealthKitManager()

        let withoutConsent = CoachViewModel.clientContext(profile: profile, health: health, previous: nil)
        #expect(!withoutConsent.localizedCaseInsensitiveContains("bariatric"))

        profile.shareHealthHistoryWithCoach = true
        let withConsent = CoachViewModel.clientContext(profile: profile, health: health, previous: nil)
        #expect(withConsent.contains("sleeve gastrectomy"))
        #expect(withConsent.contains("protein, hydration"))

        let forNotifications = CoachViewModel.clientContext(profile: profile, health: health, previous: nil, includeHealthHistory: false)
        #expect(!forNotifications.localizedCaseInsensitiveContains("bariatric"))
        #expect(!forNotifications.localizedCaseInsensitiveContains("sleeve"))
    }

    @Test func missingSurgeryDetailsAreHandled() {
        let history = HealthHistoryContext(
            bariatric: .yes, surgeryType: nil, surgeryDate: nil, clinicianNutritionGoals: "", clinicianProteinGrams: nil,
            clinicianExerciseRestrictions: "", lastClinicalReview: nil, notes: ""
        )
        let lines = CoachViewModel.healthHistoryLines(history)
        #expect(lines.contains("  • Previous bariatric surgery."))
        let none = HealthHistoryContext(
            bariatric: .preferNotToSay, surgeryType: nil, surgeryDate: nil, clinicianNutritionGoals: "", clinicianProteinGrams: nil,
            clinicianExerciseRestrictions: "", lastClinicalReview: nil, notes: ""
        )
        #expect(CoachViewModel.healthHistoryLines(none).isEmpty)
    }
}
