# Vanity — Audit & Phased Improvement Plan

Living checklist for the product improvement plan. Update it as phases land.

## 1. Architecture (as audited, Nov 2026)

- **SwiftUI app, iOS 17+, Swift 6**, Xcode project `GoalTracker.xcodeproj` with file-system-synchronized groups (new files are picked up automatically).
- **State:** `@Observable` managers injected through the environment from `GoalTrackerApp`: `HealthKitManager`, `UserNotificationManager`, `CoachNotesManager`, `AppRouter`.
- **Persistence:** SwiftData models `GoalProfile`, `ProgressPhoto`, `WorkoutRoutine`, `WeightMilestone`, `SpiritualQuote`, `CoachCritique`, `CoachNote`. No migrations plan yet: new stored properties need defaults.
- **Pure logic (unit tested):** `TargetEngine`, `WeightGoalEngine`, `EnergyBalance`, `IntakeAssessor`, `NotificationContent`, `ReminderSlot`/`DailyRhythm`, `CoachService` request/response shaping.
- **AI:** `CoachService` calls the Messages API directly (`sk-ant-` key in Keychain) or through the Cloudflare Worker in `proxy/` (access code). Opus for photo verdicts, Sonnet for check-in notes. Structured JSON-schema output with refusal/truncation handling.
- **Background:** `BGAppRefreshTask` rewrites tomorrow's coach notes overnight; notifications are rescheduled 7 days ahead on every foreground.

## 2. Feature → source map

| Feature | Files |
| --- | --- |
| Dashboard | `Views/Dashboard/DashboardView.swift`, `DashboardCards.swift`, `WorkoutViews.swift`, `ViewModels/DashboardViewModel.swift` |
| Goal math & status | `Managers/TargetEngine.swift`, `WeightGoalEngine.swift`, `IntakeAssessor.swift`, `EnergyBalance.swift` |
| Apple Health | `Managers/HealthKitManager.swift`, `Models/WorkoutSummary.swift` |
| Manual weigh-ins | `Views/Dashboard/LogWeightView.swift` → `HealthKitManager.saveWeight` |
| Transformation photos | `Views/Transformation/*`, `ViewModels/TransformationViewModel.swift`, `Models/ProgressPhoto.swift`, `Managers/ImageProcessing.swift`, `CameraController.swift` |
| AI Coach verdicts | `Views/Coach/CoachView.swift`, `ViewModels/CoachViewModel.swift`, `Managers/CoachService.swift`, `Models/CoachCritique.swift` |
| Check-ins / notifications | `Views/Mindset/MindsetView.swift`, `CheckInsView.swift`, `Managers/UserNotificationManager.swift`, `CoachNotes.swift`, `CoachNotesManager.swift`, `NotificationContent.swift`, `NotificationPresenter.swift`, `Models/ReminderSlot.swift`, `CoachNote.swift` |
| Emergency Reset | `Views/Mindset/EmergencyResetView.swift` |
| Plan, milestones, routines | `Views/Plan/*`, `Models/WeightMilestone.swift`, `WorkoutRoutine.swift` |
| Goal & daily rhythm setup | `Views/Settings/GoalSetupView.swift`, `DailyRhythmView.swift` |
| Credentials | `Managers/KeychainStore.swift`, `proxy/src/index.js` |

## 3. Phase 1 audit findings (fixed in Phase 1)

**Goal / calorie math (old `TargetEngine`)**
1. Required daily deficit = `remaining × 3500 / days`, with no cap. For 330 → 300.7 lb by Dec 14, 2026 that's ~2,629 kcal/day (5.3 lb/week).
2. The status compared **today's partial deficit** against that full-day requirement, then said "Add a workout or tighten intake" (**PUSH HARDER**) or "Close the gap" (**DEFICIT NEEDED**). An unsafe target became the behavioral instruction.
3. "Calories consumed" was a plain sum with no notion of time of day, missing logs, or zero vs. not-logged. At 9 AM with 190 kcal logged, the user was graded as if that were the whole day. Late in the day an **empty log looked like a huge deficit and scored ON TRACK**, which rewarded not logging (or not eating).
4. A trend faster than any safe pace (e.g. 3.5 lb/week) counted as ON TRACK with no caution.
5. A 2 lb/week warning existed, but it was informational only; the status and the coach still chased the deadline.
6. The resting-energy fallback prorated with a fixed 86,400-second day (off on DST days) and only applied when basal was exactly 0. A watch that was off for half the day silently halved resting burn.
7. Trend used any 2 readings over 3+ days, which is noisy enough to swing the status.

**HealthKit energy aggregation (old `HealthKitManager.refresh`)**
- Active energy: `HKStatisticsQuery` cumulative sum for today. HealthKit merges overlapping samples from multiple sources by source priority, so Watch + Peloton *samples* weren't double-counted there.
- Workouts: `activeEnergyBurned = max(sampledActive, sum of today's workout calories)`. Problems:
  - The same ride recorded by Watch **and** Peloton was summed twice inside the workout total.
  - Taking the max dropped Peloton calories that existed only on the workout whenever the Watch's all-day total was larger.
  - Workouts crossing midnight were credited entirely to the day they started.
- Basal energy wasn't observed, so the dashboard didn't refresh when it synced.

**Coach**
- The client context sent "Deficit X vs 2,629 kcal required per day", so the AI was being asked to enforce the unsafe target.
- The Drill Sergeant tone told the model to roast the user's body ("that gut didn't build itself"). The plan's safety standard (3.4) forbids that, and it conflicted with the shared safety rules added here, so it was pulled forward from Phase 3.

## 4. Phase 1 — what changed

- `WeightGoalEngine` (new): keeps the **aspiration** (target, date), the **deadline math** (required pace, rough 3,500 kcal/lb estimate, shown as context only) and the **sustainable plan** separate. `PacePolicy`: 0.5 lb/week minimum, 1 lb/week steady, max = min(1% body weight, 2 lb/week), deficit capped at 1,000 kcal/day. Feasibility: achieved / comfortable / ambitious / exceedsSustainable / deadlinePassed. Projects weight at the deadline and target date as **ranges**, suggests a new date when the deadline doesn't fit, and flags weigh-ins older than 7 days.
- `IntakeAssessor` (new): uses the user's own Daily Rhythm meal times. States: notTracking / noEntriesYet / missingLogs / inProgress / complete. Foods within 60 minutes count as one eating occasion. A deficit is only judged on a complete day. Low intake on a complete day gets a supportive check-in, never praise. Flags missing protein data.
- `EnergyBalance` (new): observed vs. estimated resting energy (including partial-watch days), app-only workout calories added per workout window, duplicate sessions merged (≥50% overlap of the shorter one), partial overlaps not double-counted, midnight-spanning workouts prorated, DST-correct day length, data-quality issues surfaced.
- `TargetEngine`: composes the three engines. New statuses: ON TRACK, BUILDING MOMENTUM, NEEDS ATTENTION, LOGGING INCOMPLETE, GOAL NEEDS ADJUSTMENT, GOAL REACHED, plus AWAITING DATA and TARGET DATE PASSED. Graded on the measured trend (3+ readings over 5+ days) against the *recommended* pace. A fast trend is flagged, not rewarded.
- `HealthKitManager`: one `now` per refresh, food entry timestamps, protein presence, prior-week logging check, per-workout sampled energy, basal energy observed.
- Dashboard: status card shows trend vs. plan and a goal-adjustment panel with projections. The deficit card reads "Today So Far" until the day is complete, labels estimates, and lists data-quality notes. The visual style is unchanged.
- Coach: context carries plan, feasibility, completeness and data notes. Shared `CoachSafety.rules` in both prompts for all tones. Drill Sergeant challenges habits, not bodies.

## 4b. Phase 1.5 — Aggressive Goal Mode & pace tracking

- **Goal modes** (`Models/GoalIntensity.swift`): Standard / Aggressive / Clinician-Guided, stored on `GoalProfile` (`goalIntensityRaw`, defaulted, so existing profiles migrate in place). The goal weight and date are never changed by the app in any mode.
- **Aggressive acknowledgment**: shown once per text version (`AggressiveMode.acknowledgmentVersion`), stored with date and the required pace at the time. If the required pace rises ≥ 1 lb/week afterwards, YOUR PACE and the coach surface a new warning.
- **Clinician-Guided**: an optional clinician pace limit replaces general guidance for feasibility, but the app's suggested deficit stays capped at 1,000 kcal/day. Without an entered value, general guidance applies.
- **Weight-loss history** (`Views/Settings/WeightLossHistoryView.swift`): optional bariatric history, surgery type/date, clinician nutrition/protein/exercise guidance, last review, notes. It never changes the pace. It's sent to the coach only with `shareHealthHistoryWithCoach`, and never in the check-in (notification) context.
- **Goal history** (`Models/GoalChange.swift`): appended only when the user changes the goal or mode.
- **`WeightTrendService`**: one median per local day (absorbs duplicate syncs), Theil–Sen slope over 14- and 28-day windows (14: 4+ days over 7+; 28: 6+ days over 14+), IQR uncertainty band, 7-day smoothing that never bridges gaps, stale after 7 days without a weigh-in. It replaces the old least-squares `weeklyLossRate`.
- **`GoalForecastService`**: `PaceAssessment` (required vs. actual, tolerance max(0.25, 10% of required) → AHEAD / ON PACE / BEHIND / INSUFFICIENT DATA / GOAL REACHED / DEADLINE PASSED) and `GoalForecast`. It uses the slower of the two trends, gives ranges, lowers confidence beyond 4×/8× the observed span, and doesn't project from flat, rising, stale or thin trends or beyond two years.
- **Separation**: `TargetSnapshot.status` is daily accountability. `TargetSnapshot.pace` is the trajectory against the user's own deadline. GOAL NEEDS ADJUSTMENT is Standard-only.
- **Dashboard**: new **YOUR PACE** card after the Target Engine card. In non-standard modes the status card shows a "safer alternative (optional)" panel instead of asking the user to move the date.
- **Edge fix**: a deadline of *today* is no longer reported as passed.

## 5. Checklist

### P0 — Phase 1 (done, pending device testing)
- [x] Separate goal / deadline pace / sustainable plan (`WeightGoalEngine`)
- [x] Feasibility, projected weight at deadline, projected target date, suggested date
- [x] Time-aware intake completeness (`IntakeAssessor`)
- [x] HealthKit energy audit: duplicates, overlaps, app-only workout calories, missing/partial basal, day boundaries, DST
- [x] Data-quality warnings on the dashboard
- [x] Coach context + safety rules updated
- [ ] Verify on device with real Feelfit / Carb Manager / Peloton / NRC data (simulator has no Health data)

### Phase 1.5 (done, pending device testing)
- [x] Goal modes + one-time versioned acknowledgment + elevated-risk indicator
- [x] Optional bariatric / clinician history with coach consent; excluded from notifications
- [x] Robust actual pace (Theil–Sen, 14/28-day), required pace, pace difference, trajectory status
- [x] Trend-based forecast with ranges and confidence; never modifies the goal
- [x] YOUR PACE card; coach pace/mode context
- [ ] Device check of the YOUR PACE card and settings flows with real data

### P1 — Phase 2/3
- [x] Chart the `WeightTrendService` smoothed line and the forecast (services exist since Phase 1.5)
- [x] Chart: actual + smoothed + goal trajectory + forecast, 7/30/90-day ranges; no smoothing across gaps (`WeightChartModel`, `WeightTrendCard`)
- [x] Compact top dashboard summary with the next action (`TodaySummaryCard`, `NextActionAdvisor`)
- [ ] Coach Q&A over the user's own data; persistent coaching context in SwiftData
- [ ] Daily commitments (accept / edit / dismiss / complete)
- [ ] Verdict 2.0: behavior score separate from scale outcome, data confidence, change since last review

### P2 — Phase 4/5
- [ ] Guided front/side/back photos; timeline and monthly comparisons; conservative AI photo language
- [ ] Rule-based personalized check-ins (workout done, log stale, commitments met)
- [ ] Weekly report (save, share as image/PDF on user action)
- [ ] Consistency achievements (never for deficits or speed)
- [ ] Body measurements (waist, hip, chest, body-fat estimates via HealthKit)

### P3 — Phase 6/7
- [ ] Data export and local backup; deletion warnings; AI privacy disclosures
- [ ] Hosted-AI design: per-user auth, server-held key, rate limits, minimal health data, opt-in images
- [ ] Accessibility pass (Dynamic Type, labels, contrast), UI regression tests

## 6. Known limitations / open questions
- Pace guidance is general adult guidance. The app has no age or medical inputs, so it can't personalize beyond body weight. Anyone with a medical condition should set their pace with their doctor.
- Apple Health can't tell "read permission denied" apart from "no data". Both appear as "not tracking".
- Food apps that write one daily total sample (rather than per-meal samples) look like a single eating occasion and will read as "log incomplete".
- Whether `HKStatisticsQuery` prorates samples that straddle a workout window's edges is unverified. With minute-level Watch samples the error is small.
- The fasting-focused check-in prompts (`NotificationContent`, notes categories) follow the user's chosen skip-breakfast routine. Review them in Phase 5.
