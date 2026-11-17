# AGENTS.md — Diel

## Product

Diel is a personal iPhone app with three daily dials (Readiness, Load, Sleep) from the
user's Garmin Cirqa band, read through the Garmin Connect Personal API. Personal use only; it is
not distributed. `DESIGN.md` holds the design rules; read it before any UI work.

This public repository holds the app and ScoringKit sources only. The owner's real
Garmin fixtures, the unit and UI tests that read them, the build plan and the
verification evidence stay in a private repository.

## Dial meanings

- **Readiness:** Diel's v2.2 estimate. HRV and daily RHR trends are normalized
  exponentially weighted means with a three-calendar-day half-life. HRV uses ln
  nightly Garmin HRV; display exp(mean) in ms. Complete valid past readings retain
  decaying weight beyond seven days. Trend eligibility independently needs at
  least three complete readings in the last seven calendar days. Missing nights
  add no observation. Never relabel Garmin daily RHR as overnight RHR.
  Reference distributions use qualifying dates of the same causal EWMA series
  in the preceding 60 calendar days, excluding the displayed day, minimum 14
  qualifying points, arithmetic mean and sample SD. The series retains older
  decayed inputs and does not restart at the reference boundary. Acute HRV and
  daily RHR use prior-60-day individual-reading references, minimum 14 complete
  readings. Last-night HRV and acute daily RHR remain separate; partial daily RHR
  is acute-only, never an EWMA or reference observation.
  Weights are HRV trend 0.35, acute HRV 0.15, RHR 0.25, acute sleep 0.10 and
  three-night sleep 0.15. RHR splits 75% trend/25% acute. Sleep uses duration/need
  for the last night and sum(duration)/sum(need) for exactly three complete
  calendar-night pairs. Each deviation is (adequacy - 1)/0.10, capped at [-3,+1].
  Surplus can add and offset deficit; need is neutral. Sleep has no historical
  SD or reference-count gate. Missing/partial duration or need remains missing.
  Physiological deviations cap at ±3. Normalize the five-term weighted sum by
  sqrt(sum of squared weights), sqrt(0.24), then apply center 50 and gain 15.
  Explicitly clamp the final score to 5-95, retaining pre-clamp attribution.
  Zero physiological SD yields zero only for an exactly neutral numerator;
  otherwise missing. No fitting or adaptive retuning. Preserve v1, original v2
  and v2.1 as frozen controls.
  Always expose latest HRV, EWMA HRV/RHR trends with recent counts, references and
  sleep evidence, including missing/partial states. A trend never replaces a
  missing current night. Why-lines first keep families pushing in the score's
  direction from center 50, then rank absolute signed family totals: HRV trend
  plus acute, aggregate RHR, and acute plus three-night Sleep, in that tie order.
  Name the strongest weighted part in that direction within the selected family.
  A Sleep driver says "Short sleep pulled it down" rather than repeating Sleep's line.
  At exactly 50 retain the absolute ranking. After three
  consecutive emitted direction-specific reasons, use the second-ranked family
  if its magnitude is within two points and the winning reason would repeat.
  Missing/unavailable days reset the streak. Resolve chronologically from local
  history, independent of displayed range and future inputs. Do not infer fatigue
  or maladaptation diagnoses. "Diel estimate" is detail-only; keep the Settings
  disclaimer. Package defaults retain original v2; the app explicitly selects
  `ReadinessV2Config.v2_2`. Use versioned EWMA metadata for the active trend,
  never silently reinterpret the frozen seven-day rolling-reference slots.
- **Sleep:** Garmin's optional `sleepScores.overall.value`, with band colours.
  Attribute it as Garmin's in the detail screen. Diel's duration and continuity
  measures are components, never a replacement primary score when Garmin is missing.
- **Load:** Diel's all-day heart-rate load, using same-day resting HR and timestamped
  `dailyHeartRate` readings. Banister TRIMP is minutes × HR reserve × 0.64 ×
  exp(1.92 × HR reserve), with reserve `(HR - rest)/(max - rest)` bounded to 0–1.
  At/below rest contributes zero. Use real sample intervals capped at five minutes.
  Use Garmin zones' max HR when available; otherwise use the highest reliable HR
  in the causal 90-calendar-day history, rejecting isolated sample spikes.
  The fixed fixture-calibrated scale uses k = 500:
  `round(100 × (1 - exp(-TRIMP/k)))`, bounded
  to 0–100, with ring fraction value/100. A day's running value never decreases
  across refreshes. Preserve partial collection evidence while displaying running
  load. No HR data shows "–"; missing calibration must never invent HR or TRIMP.
  Under 10 says "No training yet"; otherwise "Light so far" or "Heavier than usual
  so far", compared with the previous 28 days' same-time typical when available,
  otherwise the complete daily median. Load always uses the `load` colour,
  without grades. Per-activity rows retain Garmin's native activity load.

Missing stays missing. Preserve source/date provenance and collection coverage.
A historical trend never replaces a missing current night. Garmin per-activity
load remains in native units and can exceed 100; only Diel's daily Load uses the
bounded scale above.

## Repo layout

```text
Diel.xcodeproj     the Xcode project (scheme: Diel)
Diel/              app target sources
ScoringKit/        Swift package for baselines and scores, no UI
design/            app icons and the README banner
scripts/           build helper scripts
```

## Stack

Swift 6, SwiftUI, iOS 27 deployment target, Observation (`@Observable`), SwiftData, Swift Charts,
Swift Testing, `URLSession` with async/await. No third-party packages without a yes from the user.

## Garmin Personal API

- **Auth:** the API key is exchanged for an access token with
  `POST https://personal.connectapi.garmin.com/personalapitoken-service/personal-api/personal-api-key/token`
  and header `Authorization: ApiKey <key>`. The token is valid for 24 hours; there are no
  refresh tokens, so get a new one from the key.
- **Endpoints** the app uses (paths from Garmin's reference client):
  - Sleep: `/sleep-service/sleep/dailySleep?date=`, `/sleep-service/sleep/dailySleepSummariesByDate`
  - HRV: `/hrv-service/hrv/{date}`, `/hrv-service/hrv/daily/{start}/{end}`
  - Heart rate: `/wellness-service/wellness/dailyHeartRate?date=`
  - Body Battery: `/wellness-service/wellness/bodyBattery/reports/daily`
  - Stress: `/usersummary-service/stats/stress/daily/{start}/{end}`
  - Daily summaries: `/usersummary-service/v2/dailysummaries`
  - Activities: `/activitylist-service/activities/search/activities`,
    `/activity-service/activity/{id}`, `/download-service/files/activity/{id}` (ZIP with .FIT)
- Confirm the data base URL and response schemas in the Swagger docs
  (https://developer.garmin.com/gc-developer-program/personal/swagger-docs/) and the reference
  client (https://github.com/garmin/connect-personal-api-python) before writing client code.
  Swagger is the contract for model optionality: a property not marked required is
  optional. Fixtures establish observed wire representations and regression examples,
  not requiredness. Preserve nullable readings and never invent missing values.
- **Pull-only:** the app syncs on launch and in a morning `BGAppRefreshTask`.
- **The key:** stored only in the iOS Keychain, entered by the user on the app's settings screen.
  Never put it in code, tests, fixtures, logs, print statements, commits or prompts. Agents never
  ask for it, never read `~/.config/garmin/` and never call the live API. Never commit real
  Garmin responses or personal measurements to this repository.

## Design rules

Dark mode only in v1. Liquid Glass is for navigation, controls and tappable dials.
Dense data cards and chart plots stay solid or lightly tinted. A dark living canvas
uses data-meaningful light and motion, with complete accessibility fallbacks.
Identity anchors and performance requirements are in `DESIGN.md`.

## Build and verify

- **Build** (the compiler is the typecheck): XcodeBuildMCP `build_sim` with scheme `Diel`,
  project `Diel.xcodeproj`, on the newest iPhone Pro simulator installed. CLI equivalent:
  `xcodebuildmcp simulator build-sim --scheme Diel --project-path ./Diel.xcodeproj --simulator-name "iPhone 18 Pro"`
- **Tests:** not included here; they read real Garmin fixtures and live in the private
  repository. ScoringKit builds with `swift build --package-path ScoringKit`.
- **Lint:** `swift format lint --recursive --strict Diel ScoringKit`. If the toolchain has
  no `swift format`, skip lint and say so in the report.
- **UI changes:** build, run, capture simulator screenshots and review against
  `DESIGN.md` and its identity anchors. Reference screenshots are not a prerequisite.
- **Done means:** zero warnings and the UI satisfies `DESIGN.md`.

## Reports

Open each report with at most 6 lines covering what changed, what remains, and
anything needing the user's decision. Follow with links to details. Put test
plumbing, commands, logs and full verification evidence in the linked file, not
in the opening summary.

## Delegation

Subagent work follows the `orchestrator and executors` skill: load it before spawning any subagent. This repo
supplies the values that skill leaves open:

- **Checks:** build, lint and tests as in "Build and verify". The build is the typecheck.
- **High-risk areas for review:** Keychain and Garmin key handling, SwiftData models and
  migrations, ScoringKit formulas. A review also runs at the end of every phase.
- **File ownership:** only one subagent at a time touches `Diel.xcodeproj`.
- **Key rules in specs:** any spec touching networking, settings or the Keychain quotes the key
  rules from "Garmin Personal API".
- **Main agent edits directly:** `AGENTS.md`, `DESIGN.md`.
- **Where to stop:** without asking: commit to the current branch after a green build and
  review. Always needs a yes: push, merging to `main`, adding a package,
  changing the bundle ID, signing, capabilities or entitlements, deleting files outside the
  task, uploading to TestFlight, and anything involving the real Garmin key.
