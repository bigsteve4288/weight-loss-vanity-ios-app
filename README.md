# Vanity

*Vanity, for your health.*

A high-accountability weight loss and mindset dashboard for iOS. It tracks a 34 lb loss toward a target birthday using live Apple Health data.

**Stack:** SwiftUI · SwiftData · HealthKit · Swift Charts · UserNotifications · iOS 17+ · Swift 6

## Features

| Area | What it does |
| --- | --- |
| **HealthKit hub** | Reads body mass (Feelfit scale), dietary energy, carbs, protein and fat (Carb Manager), and active + basal energy burned. Observer queries refresh the dashboard as new samples arrive. Manual weigh-ins are written back to Health. |
| **Target engine** | Current vs. target weight (start − 34 lb), a live countdown to your birthday, the required daily deficit, today's actual deficit (resting + active − consumed), and a 14-day weight trend. The status is one of **ON TRACK**, **PUSH HARDER TODAY** or **DEFICIT NEEDED**. It also warns you if the required pace is above 2 lb/week. |
| **Transformation** | Baseline "Then" photo next to your latest progress photo, or an overlay mode with an opacity slider. Any past photo can be used as the "Then" image. |
| **Mindset** | Daily lock-screen notifications with live numbers, a rotating quote and your baseline photo attached. The **Emergency Reset** button opens a full-screen box-breathing and grounding screen. |
| **AI Coach** | Sends your THEN and NOW photos plus your stats to Claude (`claude-opus-5-5`) and gets back a graded verdict: what it sees, how far you are from THEN, what to fix, and 3 orders for today. Tone can be Supportive, Blunt or Drill Sergeant. Past verdicts are saved and fed into the next one. |
| **Training** | Reads workouts from Apple Health (Nike Run Club, Peloton, Apple Watch) for the dashboard, the Plan tab and the coach. |
| **Plan** | SwiftData-backed workout routines, weight milestones (auto-marked when you hit them) and a spiritual quote log. |

The home-screen name is **Vanity**. The Xcode project, target and bundle ID are still named `GoalTracker`.

## Project layout

```
GoalTracker/
├── GoalTrackerApp.swift, RootView.swift
├── Models/        SwiftData models: GoalProfile, ProgressPhoto, WorkoutRoutine, WeightMilestone, SpiritualQuote
├── Managers/      HealthKitManager, UserNotificationManager, TargetEngine (pure math), NotificationContent, ImageProcessing
├── ViewModels/    DashboardViewModel, TransformationViewModel
├── Views/         Dashboard, Transformation, Mindset, Plan, Settings
└── Theme/         Gold / black / red palette, glass cards
Config/GoalTracker.entitlements   HealthKit capability
GoalTrackerTests/                 Swift Testing unit tests for the target engine
Design/make_icon.swift            Renders the app icon: swift Design/make_icon.swift AppIcon.png
```

The Info.plist is generated from build settings. These keys are set on the GoalTracker target:

- `NSHealthShareUsageDescription`: reading weight, nutrition and energy data
- `NSHealthUpdateUsageDescription`: saving manual weigh-ins

## Setup

1. Open `GoalTracker.xcodeproj` in Xcode 16 or later.
2. Select the **GoalTracker** target → **Signing & Capabilities** → choose your **Team**. If the bundle ID `com.bigsteve4288.goaltracker` is taken, change it to something unique.
3. Confirm the **HealthKit** capability is listed. It comes from `Config/GoalTracker.entitlements`.
4. Connect your iPhone and press **Run** (⌘R). HealthKit data from Feelfit and Carb Manager only exists on a real device.
5. On first launch:
   - Allow the Health permissions.
   - Enter your starting weight, goal and birthday.
   - In **Mindset**, turn on **Daily Accountability**.
   - Add a baseline photo in **Transform** so notifications include it.
6. In the Feelfit and Carb Manager apps, make sure Apple Health sync is turned on for weight, calories and macros.

### Simulator and tests

The app also runs in the iOS Simulator. Health starts empty there, so log a weigh-in from the scale button on the dashboard.

```sh
xcodebuild test -project GoalTracker.xcodeproj -scheme GoalTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Notes

- **AI Coach setup:** create an API key at console.anthropic.com → API Keys, then paste it into Transform → AI Coach. It's stored in the iPhone Keychain and never in this repo. Each verdict sends both photos and your stats to Anthropic's API.

- **Deficit math:** it assumes 3,500 kcal per pound. Resting burn comes from Health's basal energy. If there's none (no Apple Watch), it falls back to the resting-calorie value in Goal Settings, prorated by how much of the day has passed.
- **Notifications:** iOS repeating notifications can't change their content. The app schedules the next 14 days individually and rebuilds them every time it opens, so the countdown stays current. Open the app at least once every two weeks to keep them coming.
