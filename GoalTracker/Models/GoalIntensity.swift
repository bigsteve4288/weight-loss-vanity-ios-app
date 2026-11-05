import Foundation

/// How the user wants their goal treated. The goal itself (weight and date) is never changed by the app in any mode.
enum GoalIntensity: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Sustainable planning; suggests a new date when the deadline doesn't fit.
    case standard
    /// Keeps an ambitious target and fixed deadline, tracks progress against it, offers safer forecasts as alternatives.
    case aggressive
    /// Uses pace limits the user enters from their own clinician. The app doesn't verify or supervise them.
    case clinicianGuided

    var id: Self { self }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .aggressive: "Aggressive"
        case .clinicianGuided: "Clinician-Guided"
        }
    }

    var explanation: String {
        switch self {
        case .standard:
            "Plans around a sustainable pace and suggests a new date if your deadline doesn't fit."
        case .aggressive:
            "Keeps your exact target and deadline and measures you against them. Vanity still won't recommend unsafe restriction or excessive exercise."
        case .clinicianGuided:
            "Uses the pace limit your clinician gave you. Vanity records what you enter; it doesn't verify it or provide medical supervision."
        }
    }
}

enum AggressiveMode {
    /// Bump when the acknowledgment text changes meaningfully, so users see the new version once.
    static let acknowledgmentVersion = 1
    static let acknowledgmentTitle = "Aggressive Goal"
    static let acknowledgmentText = "Your chosen deadline requires faster weight loss than commonly recommended. Vanity will preserve your goal and track your actual progress, but it will not recommend unsafe calorie restriction or excessive exercise. Consider reviewing your plan with your healthcare professional."
    /// A rise this large in required pace since acknowledging surfaces a fresh warning.
    static let newWarningPaceIncrease = 1.0
}

enum BariatricHistory: String, Codable, CaseIterable, Identifiable, Sendable {
    case notAnswered
    case yes
    case no
    case preferNotToSay

    var id: Self { self }

    var label: String {
        switch self {
        case .notAnswered: "Not answered"
        case .yes: "Yes"
        case .no: "No"
        case .preferNotToSay: "Prefer not to say"
        }
    }
}

enum SurgeryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case sleeveGastrectomy
    case gastricBypass
    case other

    var id: Self { self }

    var label: String {
        switch self {
        case .sleeveGastrectomy: "Sleeve gastrectomy"
        case .gastricBypass: "Gastric bypass"
        case .other: "Other"
        }
    }
}

/// The optional health background the coach may use, only when the user has opted in.
struct HealthHistoryContext: Equatable, Sendable {
    var bariatric: BariatricHistory
    var surgeryType: SurgeryType?
    var surgeryDate: Date?
    var clinicianNutritionGoals: String
    var clinicianProteinGrams: Double?
    var clinicianExerciseRestrictions: String
    var lastClinicalReview: Date?
    var notes: String

    var hasAnything: Bool {
        bariatric == .yes || !clinicianNutritionGoals.isEmpty || clinicianProteinGrams != nil
            || !clinicianExerciseRestrictions.isEmpty || lastClinicalReview != nil || !notes.isEmpty
    }
}

extension GoalProfile {
    var intensity: GoalIntensity {
        get { GoalIntensity(rawValue: goalIntensityRaw) ?? .standard }
        set { goalIntensityRaw = newValue.rawValue }
    }

    var bariatricHistory: BariatricHistory {
        get { BariatricHistory(rawValue: bariatricHistoryRaw) ?? .notAnswered }
        set { bariatricHistoryRaw = newValue.rawValue }
    }

    var surgeryType: SurgeryType? {
        get { surgeryTypeRaw.flatMap(SurgeryType.init) }
        set { surgeryTypeRaw = newValue?.rawValue }
    }

    var hasAcknowledgedAggressiveMode: Bool { aggressiveAcknowledgedVersion >= AggressiveMode.acknowledgmentVersion }

    func acknowledgeAggressiveMode(requiredPace: Double?, now: Date = .now) {
        aggressiveAcknowledgedVersion = AggressiveMode.acknowledgmentVersion
        aggressiveAcknowledgedAt = now
        aggressiveAcknowledgedRequiredPace = requiredPace
    }

    /// The clinician pace limit, only in Clinician-Guided mode and only if one was actually entered.
    var effectiveClinicianMaxPoundsPerWeek: Double? {
        guard intensity == .clinicianGuided, let pace = clinicianMaxPoundsPerWeek, pace > 0 else { return nil }
        return pace
    }

    var healthHistory: HealthHistoryContext {
        HealthHistoryContext(
            bariatric: bariatricHistory,
            surgeryType: bariatricHistory == .yes ? surgeryType : nil,
            surgeryDate: bariatricHistory == .yes ? surgeryDate : nil,
            clinicianNutritionGoals: clinicianNutritionGoals,
            clinicianProteinGrams: clinicianProteinGrams,
            clinicianExerciseRestrictions: clinicianExerciseRestrictions,
            lastClinicalReview: lastClinicalReviewDate,
            notes: weightLossNotes
        )
    }
}
