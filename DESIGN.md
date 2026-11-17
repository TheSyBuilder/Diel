# DESIGN.md — Diel

Diel answers three questions every morning: am I ready, how hard have I worked, how did I sleep.
Keep three dials: Diel Readiness estimate, all-day Diel Load, and Garmin Sleep Score.
Each screen answers one question. The number comes first, the reason second, the raw data third.
Diel feels alive. Motion and light carry meaning, and they're tied to the data.
Darkness keeps the numbers clear; changes in light, movement and touch explain what
is happening in the data.

## Identity anchors

These never change. Every new interaction must say which anchor it builds on.

- **The dial:** one ring component, the same everywhere.
- **You against your own baseline:** the normal-range band behind every chart.
- **Colour means something:** the selected theme owns score and Load colouring.
  Ember uses warm flows, Lunar and Classic use solid score bands. Ungraded
  measurements stay neutral and Load never gains a health grade.
- **Big rolling numerals on a dark, living canvas.**
- **Every number has its reason:** no score without its why-line.

Use these anchors to judge new ideas, not to freeze the interface. A new effect
must explain a value, a reference, a selection or a real state change. It must
have a complete Reduce Motion alternative and meet the 120Hz performance gate.

## Tokens

Define these once, in one file, and use only them. No hard-coded colours, sizes,
radii, motion durations or light intensities in views.

### Colour and themes (dark mode only in v1)

Ember is the default. The table below describes its palette. Theme values are
read from the SwiftUI environment throughout the app, including sheets, charts
and shared text styles. Spacing, content, interactions and scoring stay the same.

| Token | Hex | Use |
| --- | --- | --- |
| `canvas` | `#0A0A0A` | Screen background |
| `surface` | `#161514` | Cards |
| `surfaceRaised` | `#24211F` | Pressed cards, sheets, dial track and solid accessibility fallback |
| `hairline` | `#2E2A27` | Dividers, chart baseline, card borders where needed |
| `textPrimary` | `#F7F5F3` | Numbers, titles |
| `textSecondary` | `#A7A19C` | Labels, why-lines |
| `textTertiary` | `#918B86` | Units, timestamps, captions |
| `error` | `#EE3E55` | Errors and destructive actions |
| `brand` | `#FF5A1F` | App icon and sync accent |
| Score scale | `#EE3E55` → `#FF5A1F` → `#FF9A1F` → `#FFD23F` | Fixed stops at 0, 0.45, 0.75, 1 |
| Load scale | `#C2410C` → `#FF8A3D` | Fixed stops at 0 and 1, always orange |
| Ember depth | `#2C1508` | Top glow fades through this into canvas |

Ember uses only red, orange, yellow and neutrals. Define the two scales and a
clamped sRGB interpolation helper in `DesignTokens.swift`. Do not duplicate hex
values in views. Readiness and Sleep colours follow the actual score divided by
100, independently of the frozen scoring bands. Those bands retain their existing
meaning in VoiceOver. Error red remains a separate semantic token even though it
shares the score scale's first colour.

Colour carries meaning:

- In Ember, Readiness and Sleep rings flow from a darker shade of their tip colour
  to the tip colour. The tip comes from the fixed score scale. Their names,
  glyphs, tip caps and selected chart points use the interpolated colour at the
  actual tip. Number text always uses `textPrimary`.
- In Ember, Load uses its orange scale, with tip colour from its ring fraction.
  Its name and glyph use that tip lightened only enough to reach 4.5:1 against
  canvas. The ring and caps keep the true scale. It never acquires a red/yellow
  health grade. Non-ring Load marks use the orange token.
- Sleep remains Garmin's score with attribution in detail. Colour changes do not
  alter its value, availability or scoring cutoffs.
- Body Battery, HRV Status, stress and other ungraded values remain neutral.
  Sleep composition uses the selected theme's stage shades, defined in tokens.

### Theme sets

A Theme supplies canvas, surface, surfaceRaised, hairline, all three text roles,
score colouring, Load colouring, background glow, error colour and app icon name.
The environment default is Ember. No view reads a mutable global palette.

| Token | Ember | Lunar | Classic |
| --- | --- | --- | --- |
| Canvas | #0A0A0A | #050506 | #0A0A0A |
| Surface | #161514 | #111214 | #161514 |
| Raised | #24211F | #1C1D21 | #24211F |
| Hairline | #2E2A27 | #2C2F35 | #2E2A27 |
| Primary text | #F7F5F3 | #F2F4F7 | #F7F5F3 |
| Secondary text | #A7A19C | #9A9FA8 | #A7A19C |
| Tertiary text | #918B86 | #9A9FA8 | #918B86 |
| Good | Flow | #F2F4F7 | #1EE6B4 |
| Caution | Flow | #C9A86A | #FFC233 |
| Low | Flow | #FF5F57 | #EE3E55 |
| Load | Orange flow | #A9B8D6 | #FF5A1F |
| Error | #EE3E55 | #FF5F57 | #EE3E55 |
| Brand/control accent | #FF5A1F | #A9B8D6 | #FF5A1F |
| Background glow | Warm ember | Cool silver | Readiness band tint |
| Icon asset | Diel | DielLunar | DielClassic |

Only Ember uses flowing rings. Lunar and Classic stroke the filled arc in a
single colour from the actual ScoringKit score band. Any fallback classification
uses ScoringKit's configured cut-offs, never UI-owned copies. Load is the same
single theme colour at every value in those two themes. Ring progress, running
Load values and collection coverage are independent of appearance.

Every primary, secondary and tertiary text token must pass 4.5:1 against that
theme's canvas, surface and raised surface. Report the ratios with verification.
Semantic ring colours remain the specified values and are distinct from
those three neutral text roles. Ember Load name/glyph use the minimal
contrast-adjusted tip described above.

Settings has an Appearance section with three rows: actual icon thumbnail,
Ember/Lunar/Classic name, and a checkmark on the current choice. The selection
switches immediately with a short colour transition, persists in UserDefaults,
and requests the matching alternate app icon. Ember uses the primary icon via a
nil alternate name. Honour Reduce Motion with a direct colour update; no scoring,
sync, credential or navigation state changes when selecting a theme. Keep icon
requests ordered so a slow earlier request cannot overwrite the latest choice.

### Type

SF Pro throughout, through Dynamic Type text styles. Numbers use `.monospacedDigit()` so values
don't jitter while animating.

| Role | Style |
| --- | --- |
| Dial number | 44 pt, semibold, `@ScaledMetric` so it grows with Dynamic Type |
| Detail-screen hero number | 64 pt, semibold, `@ScaledMetric` |
| Screen title | `.largeTitle`, bold |
| Section label | `.subheadline`, semibold, `textSecondary` |
| Body and why-lines | `.subheadline`, `textSecondary` |
| Units and secondary text | `.subheadline`, `textSecondary` |

### Spacing and shape

- Spacing scale: 4, 8, 12, 16, 24, 32, 48. Nothing in between.
- Screen side margin: 20. Gap between cards: 12. Padding inside cards: 16.
- One corner radius for cards: 20, continuous (`.rect(cornerRadius: 20, style: .continuous)`).
- Dense cards keep solid or lightly tinted surfaces. No decorative gradients or
  drop shadows on data cards. The ember glow belongs behind the Home header and dials only.
- Motion tokens include a point/tick pulse around 6s and a ring sweep around
  0.8s. Keep durations centralized; the pulse is a UI rhythm, not respiration.

## Living canvas

In Ember, Home has a warm ember glow from the top, orange `#FF5A1F` fading through
`#2C1508` into `canvas`. Its hue never follows the score. Strength follows the
valid displayed Readiness value, clamped linearly from roughly 0.08 at zero to
0.24 at 100. Unavailable Readiness uses the solid canvas and does not imply a score. The glow sits behind the greeting and dials, fades out before the first
card, and scrolls away with that top section. Other screens retain the dark canvas.

Every theme uses the same top glow shape, placement and fade. Lunar uses cool
silver `#D6DEEB`, strength 0.10 at zero to 0.18 at 100, fading through `#1C1E24`
into its canvas. Classic follows the actual Readiness band: good `#1EE6B4`,
caution `#FFC233`, low `#EE3E55`, strength 0.12 to 0.18, fading through a dark
shade of the same hue into canvas: good `#062E24`, caution `#33270A`, low
`#300C11`. Band changes cross-fade. Glow colours, dark
shades, strength bounds and transition duration are theme/design tokens.

The glow is static, with no ambient animation clock. Reduce Motion retains the
same meaningful light and uses direct band changes. Reduce Transparency removes
the glow and uses the solid canvas. Unavailable Readiness means no glow in any
theme. Cards and plots stay solid or lightly tinted for stable contrast. No halo,
backplate, blur or breathing glow surrounds a dial.

Builds on **colour means something** and **big rolling numerals on a dark,
living canvas**.

## Components

### Score dial

The signature element. One reusable ring component everywhere, three sizes: Home
(112 pt), detail hero (200 pt), widget (64 pt). In the app it is a tappable solid ring with large legible numerals. It has no
glass surface, halo or backplate. Static hosts reuse the same ring drawing.

- A full ring track in the selected theme's `surfaceRaised`. In Ember, a trimmed
  Circle uses an AngularGradient stroke across the filled arc, starting at
  12 o'clock and running clockwise. The start is a darker shade of the current
  tip colour, and the end is the tip colour from the score scale. A score of 31
  stays red throughout; 82 reads orange-gold. Load uses the same treatment with
  its own orange scale. During a sweep, both endpoints follow displayed progress.
- Ember uses the score scale for Readiness and Sleep and the orange scale for Load.
  Lunar and Classic use solid configured score-band colours and a constant Load
  colour. Only Ember has an interpolated gradient tip.
  Draw the round end cap in the interpolated tip colour for Ember, including
  during sweeps; solid themes use the same solid colour for stroke and cap.
  The dial name and glyph use the actual value's theme colour, with the
  contrast-adjusted Ember Load foreground. Missing scores use
  neutral labels; missing Load keeps its orange identity.
- Ring stroke: 10% of the diameter, round line caps, starting at 12 o'clock, running clockwise.
- Readiness and Sleep use a 0-100 value mapped to 0-100% of the ring.
- Load's number is Diel's all-day heart-rate load, rounded and bounded to 0–100.
  Its ring is value/100. Use timestamped dailyHeartRate readings, same-day resting
  HR and Garmin zones' maximum HR if available, otherwise the highest reliable
  HR in the causal last 90 calendar days. Reject isolated spikes for the maximum. A reading is supported by a neighboring
  valid reading within five minutes and 10 bpm; use the highest supported reading.
  Banister TRIMP weights each sample by its real interval, capped at five minutes;
  at/below resting HR adds zero. The fixed fixture-calibrated scale is
  `100 × (1 - exp(-TRIMP/k))`. The calculation sheet names the fixed calibrated
  k of 500 and the evidence. Re-check k in January rather than adapting it automatically.
- A day's running Load never decreases across refreshes. Morning and incomplete
  collections keep a visible running value with honest coverage; only no HR data
  shows "–". Never invent a resting HR, maximum HR or measured TRIMP when
  calibration evidence is missing. No prior-history minimum hides an available
  running value. Activity rows keep Garmin's own native load, which can exceed 100.
- Number centred inside. Use placement B from the glyph reference below the ring:
  the custom glyph beside READINESS, LOAD or SLEEP, both in the dial colour,
  in the section label style. Use explicit localized uppercase labels; VoiceOver
  keeps the natural metric names. The numeral remains free of glyphs.
- On launch, the ring sweeps from its track to the actual available value over
  about 0.8s. Numerals roll using numericText transitions as real values change,
  with monospaced digits. Do not restart launch choreography on every body update.
- Tapping the control carries the same ring and value into its detail screen.
  Match source identity and geometry for a continuous zoom/morph and reverse it
  on return. Preserve native back navigation and interrupted-gesture behavior.
  Keep native matched navigation independent of the ring drawing.
- Reduce Motion replaces ring sweeps, rolling digits and spatial morphs with a
  static value or short cross-fade. Reduce Transparency keeps the same solid ring
  with the glow-free canvas and every tap affordance.
- VoiceOver reads each dial as one element, for example "Readiness, 72, good".
  Load announces its running value and collection state without a good/low grade;
  a value under 10 includes "No training yet".

Dial interaction builds on **the dial**, **colour means something**, **big
rolling numerals** and **every number has its reason**. The why-line stays readable
and attached to the same measurement while the ring changes size.

### Why-line

One sentence under each dial explaining the number, at most about 50 characters,
no jargon. Running Load under 10 says "No training yet". Otherwise use "Light so
far" or "Heavier than usual so far", comparing with the preceding 28 calendar
days' median at the same time of day when available, otherwise their complete
daily median. The comparison is descriptive and never a health grade.
Readiness never repeats Sleep's why-line. If Sleep is its strongest family,
say "Short sleep pulled it down". Select drivers pushing in the score's direction
from center 50, including the strongest part within that family. Never substitute
an opposing physiological driver. Keep the scoring formula unchanged.
At default text size every Home why-line fits two lines without shrinking.
Durations over 60 minutes use "2h 15m", never "135 min", in every view and brief.

### Card

Solid surface or a light, data-meaningful tint, radius 20, padding 16. Dense data
cards and chart plots stay stable and legible above the canvas. One idea per
card: a headline number, at most one sentence and one visual. The morning brief
uses its requested headline and at most two sentences. Home has no
label/value lists longer than three rows. Every Home card responds to touch.
Glass is reserved for navigation and controls. Dials stay solid.

### Charts (Swift Charts)

- Colour keeps the same meaning as the dials. Load stays orange. Readiness/Sleep
  selection markers use the selected theme's score colour; the rest of the trace may stay neutral
  so a selected day's colour is not incorrectly assigned to the whole history.
- Keep the user's normal-range band behind every chart, in surfaceRaised. Use
  that metric's real reference window, units and valid observations; Readiness
  physiology now uses the preceding 60 days, not a hard-coded four weeks. The
  chart viewport of 7/30/90 days does not redefine the reference window.
- A normal band spans the full plot width only when every calendar day in the
  viewport has valid bounds. Otherwise omit the entire band, never partial blocks.
- Do not fabricate a normal range during insufficient history or put an HRV-ms
  band behind a 0-100 score. Retain the baseline context and show its unavailable
  state until valid bounds exist. A Load reference is descriptive, not a health grade.
- No vertical gridlines. At most 3 horizontal reference lines, in `hairline`.
- Axis labels and secondary text use at least `.subheadline`, `textSecondary`.
- Trends offer exactly three ranges: 7, 30 and 90 days, as a segmented control.
- Drag horizontally across a plot to scrub by calendar day. Update the date,
  selected value, reference and why-line together. Missing days stay selectable
  and show their missing state; never jump over a gap or replace it with zero.
- Emit one selection haptic when the selected day changes during scrubbing,
  never per pixel or on programmatic restoration. No tick for holding the same day.
- Keep chart scrubbing distinct from vertical scrolling/pull to sync. VoiceOver
  and non-drag controls provide the same day-by-day selection. Use a static cursor
  and direct value updates with Reduce Motion.
- Inside a plot, horizontal scrubbing takes priority over native full-content
  back pans. Vertical drags still scroll, and the leading screen-edge back gesture
  and back button keep their native behavior. Outside plots, content-back remains
  available.

Chart scrubbing builds on **you against your own baseline**, **the dial** when a
ring preview is shown, and **every number has its reason**.

## Readiness context and score ownership

Always show these together on the Readiness detail screen: last night's measured HRV in ms,
the HRV trend, and Garmin daily RHR in bpm against its reference. Include the RHR
trend and acute/three-night sleep evidence in the same context. Daily RHR is not
a verified overnight measurement. Preserve missing and partial states even when
the score is unavailable; a trend never replaces a missing acute reading.

Readiness v2.2 uses a normalized exponentially weighted mean of ln nightly HRV
and daily RHR, half-life three calendar days. Older complete readings continue
decaying beyond seven days; the seven-day interval only supplies the independent
minimum-three-reading eligibility gate. Display exp(mean ln HRV) in ms. These are
Diel trends, distinct from Garmin's weeklyAvg. Do not label them seven-day means.
The reference uses qualifying values from the same causal EWMA series on
[D-60,D), minimum 14 series points, mean and sample SD. The EWMA does not restart
at that boundary; underlying source dates may precede the reference interval.
Acute HRV and daily RHR retain individual-reading prior-60-day references with
minimum 14 complete readings. Keep units and plain missing states visible in detail.
Preserve recent reading counts, series sample counts and reference windows internally
without conflating
them. Do not display provenance or counts on screen except for the learning
figure described below.

Weights are 0.35 HRV trend, 0.15 acute HRV, 0.25 RHR, 0.10 acute sleep and 0.15
three-night sleep. RHR combines 75% clipped trend and 25% clipped acute. Sleep
uses last-night duration/need and sum(duration)/sum(need) over exactly three
complete date-matched calendar nights. Both subtract one and divide by 0.10,
one unit per 10% of need, with deviations capped at [-3,+1]. Surplus is allowed;
need is neutral. No historical sleep SD or sleep-reference warmup applies.
Always expose the latest duration and need beside the three-night evidence so
smoothing cannot hide a short night. Missing/partial sleep or need is unavailable,
never zero. Need-unit conversion remains an explicit upstream inference. Garmin
Sleep Score is not a Readiness input.

Center 50, gain 15 and physiological deviation caps ±3 remain fixed. Divide the
five-term weighted sum by sqrt(0.24) before gain, then explicitly bound the score
to 5-95. These are Diel product choices, not validated coefficients. Preserve
original v2, v2.1, v1 gain-15 and original v1 gain-20 as comparison controls.

Why-lines keep families pushing in the score's direction from center 50, then
rank the absolute signed family point totals: HRV trend plus acute,
aggregate RHR, and Sleep acute plus history. Within the winning family, name the
strongest weighted part pushing in that direction. At exactly 50 retain the
absolute ranking. After three consecutive emitted direction-specific
reasons, choose the second-ranked family if its magnitude is within two points
and the winning reason would repeat. Missing/unavailable days reset the streak.
No pattern reassurance or fatigue/maladaptation diagnosis is inferred. An
unavailable score explains blocking missing/history evidence first. References,
weighted sources, family totals and selected part remain available for detail.

The Readiness detail screen shows the "Learning your baseline" figure while the
existing v2.2 history requirements are not met. Keep any available number and
all measurement evidence visible. The figure has 60 ticks for the displayed day
and preceding 59 calendar days. Each lit tick means that day has a complete valid
HRV and daily RHR pair. Missing and partial days remain dim gaps. The centre shows
the actual count "of 60". This is a history picture, not a 60-reading score gate.
Only today's valid tick pulses; pause when offscreen, inactive or Reduce Motion
is enabled. The count is the sole explicit exception to the no-count wording rule.
Do not show this learning figure for a missing current reading when the baseline
is already ready.

The Readiness detail screen says "Diel estimate". Keep that label out of Home and
other summaries. The Settings disclaimer stays. Sleep attributes
its main number as "Garmin Sleep Score" in the calculation sheet. Detail shows
measured duration, recorded bed/wake times, stage totals and recent nights against
each night's need. Missing components do not erase a valid Garmin Sleep Score,
and a missing Garmin score never falls back to Diel's former weighted Sleep aggregate. Sleep status
cutoffs stay in ScoringKit config; existing 40/70 cutoffs remain. Colour now uses
the continuous score scale in Ember; Lunar and Classic use those status bands.

## Screens

Design from this document and its identity anchors. The identity reference
images (today, readiness, trends, glyphs-and-figures and icon-and-palette) are
kept privately. The "Themes" canvas board and theme sets in this document
supersede their earlier colours. "Warm flow dials" remains the Ember direction. New reference captures go in
`design/reference/`. Keep the dial row and glyph direction. Home's lower
half in `diel-today.png` predates the Words and density redo. Keep the current
Last night, Today so far, Body Battery and This week layouts, recoloured.
There is no prerequisite to supply or commit reference screenshots. The Words
and density redo authorizes the existing detail and Trends destinations. Apply
the selected theme across those screens and capture screenshots for the
user's visual review. Hardware acceptance remains a separate gate.


- **Home:** greeting with the date, then three dials in a row (Readiness, Load, Sleep), each
  with its name and human why-line only. Below them, show the morning brief, Last night, Today so
  far, Body Battery and This week. Readiness evidence lives in its detail screen.
  Tapping a dial opens its detail screen. The inline "Home" title appears only
  after the greeting has scrolled out of view.
  - Last night has actual duration, recorded bedtime and wake time, and a slim
    stage composition bar. The Sleep dial already gives the reason, so the card
    has no comparison or why-line. The rounded bar splits in proportion to the
    measured Deep, REM, Light and Awake totals in that fixed order. Four theme
    shades stay distinct in every theme. Short positive stages have a minimum
    visible width, never a stray hairline; zero stages have no segment. Drawing
    and hit testing share those adjusted widths. Scrubbing shows the selected
    stage name and measured total with one haptic tick per stage change. Nothing is
    selected initially. At rest, only the bed/wake row appears beneath the bar.
    A selection clears after three seconds without interaction, on both Home and
    Sleep detail. Missing
    totals stay unavailable. Never imply per-stage timing from aggregate totals.
  - Today so far has rolling steps, active minutes and active calories. Active kcal
    reads only Garmin daily summary `calories.burnedActive`, never resting or
    total calories and never a fallback when active calories are missing;
    activities use an icon, type, duration and load, never Garmin's raw activity title.
  - Body Battery has the day's curve when at least three readings exist, with
    scrubbable values and a gently pulsing latest endpoint. Merge duplicate timestamps
    deterministically, join readings with a smooth monotone curve bounded to 0–100,
    and add a soft gradient fill below. Break only for gaps over four hours. Use the
    same curve in detail. With fewer than three,
    show the latest number and its time alone. Use "at 6:12" with locale-aware
    time, never "Latest". Preserve gaps in collection. Pause motion offscreen,
    inactive or with Reduce Motion.
    Detail spans local midnight to the next midnight, with a quiet now marker
    and no future readings. Below the chart show Garmin's daily charged/drained
    totals once, today's high and low, and seven tappable bars for the recorded
    wake-up levels. Missing daily totals or wake-up evidence stay missing.
  - This week has the last seven calendar-day Readiness scores over a valid
    personal normal band. Missing days stay gaps. With fewer than three valid
    scores in those seven days, replace the chart with "Learning your baseline ·
    N of 60", using the same complete HRV/RHR pair count as the learning figure.
    With three or more scores, keep that learning line beneath the chart until
    the count reaches 60, then remove it. This is a display threshold, never a
    scoring gate. Tap opens Trends.
  Cards rise on scroll with scrollTransition, press with a spring, and roll
  actual changing numbers. Reduce Motion uses static positions and numbers.
- **Navigation:** Home, Trends and Settings tabs. Home uses `house.fill` and the tab label "Home". A score detail opens only from
  its dial on Home, retaining the dial zoom transition. The lower Home cards
  for Last night and Today so far are informational.
- **Detail (one per dial):** the hero dial with the only why-line, "Diel
  estimate" for Readiness, human explanations and measurements, then a chart.
  Say each fact once. Sleep shows one Last night summary with duration and recorded
  bed/wake times, a larger stage composition bar with Deep/REM/Light/Awake totals
  below it in that order, and seven recent nights against each night's own need. The
  same theme shades, minimum widths and stage-total scrubbing apply to detail and
  Home. Recent nights uses seven wide rounded diverging bars. The centre line
  represents each night's own need; signed minutes above or below need determine
  the bar height on a shared minutes scale. Size the space above and below need
  independently from the largest observed difference on each side, with a little
  headroom. With no extra sleep, the need line sits near the top and the chart
  is shorter. This chart uses sleep need as its
  personal comparison, without a historical normal-range band. Every night has its weekday initial
  beneath it, with no axes or legend. Missing or partial duration/need pairs show
  a faint neutral dot, never a zero shortfall. A complete pair within five minutes
  of need shows a small coloured dot on the line. Keep edge bars and selection text inside the plot.
  Bar colour follows the selected theme's score colouring for closeness to need,
  using 100 times max(0, 1 - absolute duration/need difference divided by need).
  This display colour is separate from Garmin Sleep Score. Tap or scrub shows
  a temporary callout such as "Tue · 28 min short", "Tue · 12 min extra" or
  "Tue · Met need". VoiceOver supports every calendar night, including missing
  and partial pairs, with the same difference and the recorded duration/need. Sleep source
  attribution belongs in the info sheet. Readiness and Load likewise avoid
  repeating the hero reason or measurements in later sections.
  Each detail screen has an info button opening one "How this is calculated"
  sheet. Calculation context belongs in that sheet, using plain language.
- **Trends:** Readiness, Garmin Sleep Score and Diel all-day Load over 7, 30 or 90
  days, one chart each with the correct units. Missing HR stays a Load gap; an
  incomplete day can show its available running value.
- **Settings:** native grouped Form. Appearance has Ember, Lunar and Classic rows
  with icon thumbnails and the current choice marked. Garmin has a connection
  status with a
  checkmark, Replace key opening a SecureField sheet, and red Remove key with
  confirmation. Without a key, offer Add key. Sync has a relative last-synced row
  and the next planned check, plus Sync now. A sync less than a minute ago reads
  "Just now". Sync now uses the theme accent; only Remove key is red. Planned
  checks are requests; iOS
  chooses actual background timing. The wellness disclaimer is the footer. Hide key expiry until
  phase 5 supplies the manual date. DEBUG Sample data is a small capsule with no
  source-date line. A DEBUG-only row identifies today's brief as on-device model,
  template or not yet generated, using the current morning day and visible brief.

### Custom glyphs and figures

The custom SF Symbols are `diel.readiness`, `diel.load`, `diel.sleep`, `diel.hrv`,
`diel.stages`, `diel.battery` and `diel.breathing`, drawn from
`diel-glyphs-and-figures.png` with Light, Regular and Semibold weights. Readiness
is a rising half-sun with a dot, Load three ascending bars, and Sleep a crescent
with a dot. Supporting glyphs remain neutral for ungraded measurements.

Play native symbol effects once on appear: `.drawOn` for Readiness,
`.variableColor.iterative` for Load, `.breathe` for Sleep. Reduce Motion keeps the
static glyph. These effects build on colour meaning and the shared dial identity.

Sleep detail includes one "Last night" summary and actual duration with no repeated
comparison. Endpoint labels use recorded sleep start/end times. The stage
composition uses aggregate totals only and does not imply when stages occurred.
Missing times remain unavailable. The summary builds on every number having its
reason. The composition builds on colour meaning and makes the measured totals
selectable, with a static highlight under Reduce Motion and solid theme fills
under Reduce Transparency. Keep totals below it. The installed `Diel.icon` and
app icon catalog settings
must remain untouched.

All scroll content, including Settings Forms and detail screens, has enough bottom
space for its final row to be fully visible above the floating tab bar at the end
of a scroll.

### Morning check-in

The local day starts at 4:00 AM. On its first open, cover the scores with a
full-screen, solid-canvas sheet asking "How do you feel?". Show five large
buttons numbered 1–5 and only the endpoint labels "Drained" and "Great".
"Skip" records a skip for that day. One tap saves locally before dismissing;
then the dials reveal with their existing sweep. Reduce Motion uses direct
values. A selection haptic marks a saved rating. VoiceOver introduces the group
as "Rate how you feel, 1 drained to 5 great" and exposes each rating button.
Keep every button reachable at accessibility text sizes. A small "Feeling 4"
chip under Home's greeting reopens today's answer; skipped days may check in
from the same location. Never let an unsaved dismissal count as a check-in.

This builds on **every number has its reason**: the answer is the person's own
rating, recorded before Diel's scores can influence it. Theme control colours
show selection without giving the rating a health grade. Reduce Transparency
retains solid surfaces. Full local history remains available for January's
Readiness review; it never adjusts scoring automatically.

### Morning brief

The first card under the dials contains one headline of at most eight words and
a body of at most two sentences, around 45 words. It opens Readiness detail.
Write about known facts when some evidence is missing. Mention the missing piece
in a few words; do not replace available scores and sleep with a generic warning.
Use a solid theme card and a short text fade; Reduce Motion shows text directly.
The brief connects computed scores, their reasons, sleep versus need, load versus
usual, the check-in and baseline/missing states. It adds no measurements or
medical interpretation. Running Load is expected and does not by itself
make the brief generic or unavailable. A short night, Readiness near 50 and a
check-in of 3 should yield specific measured evidence. If the answer disagrees
with Readiness, acknowledge it
kindly. Missing data and a learning baseline never justify a guessed story.
Time wording follows local time; never say "this morning" after noon.
No exclamation marks or instructional filler.

Build on **every number has its reason** and **you against your own baseline**.
Generate after the check-in (including skip) and morning sync settle, using only
computed, identifier-free values. Apple's on-device model uses guided generation;
the simulator and unavailable models use a deterministic template. Reject model
numbers absent from the input. Cache locally for the day; any score change,
including rising Load, schedules regeneration at most once per 30 minutes.
Coalesce changes during the cooldown and regenerate when it expires, including
after relaunch. No remote model, raw Garmin payload or credential enters this path.

### Reminders

Settings has a "Reminders" destination with an off-by-default toggle and native
time controls: "First reminder" defaults to 8:00 and "If missed" to 10:30.
Ask notification permission only when the person enables reminders. These are
local notifications. The first says "How do you feel this morning?"; the second
says "Still time for your check-in.". A rating or skip cancels that day's missed
reminder. Tapping either opens the check-in sheet. Theme controls, native focus,
solid accessibility surfaces and static time values preserve the existing
navigation and **every number has its reason** anchors.

## Liquid Glass

Glass marks navigation and controls. Use native rendering for those controls.
Dials use solid ring strokes with no glass, halo or backplate.

- Glass: tab bar, toolbars, floating sync control and trend range control.
- Solid or lightly tinted: dense data cards, chart plots, lists and sheet content.
- The ember glow stays behind the Home header and dials. It does not extend
  through cards or change hue with scoring bands.
- Reduce Transparency replaces custom glass with solid surfaceRaised. Preserve
  borders, contrast, hit targets, selected states and every number/why-line.
- Test native and custom glass together; do not stack custom glass on top of a
  control that already supplies its own material.

Builds on **the dial**, **colour means something** and **big rolling numerals**.

## Motion, sync and haptics

Short value changes and ring sweeps settle in about 0.8s or less. The Body
Battery current-point pulse and learning tick are the only slow repeating effects. Use smooth
springs for direct interaction and a slow ease-in/ease-out for ambient breathing.
All clocks stop when their surfaces are not visible; no per-frame scoring, store
queries or network work. Numeric transitions use actual values, not fake telemetry.

Pull to sync drains the dial rings into a clearly marked syncing presentation,
then refills each as its validated updated result becomes available. Keep prior
valid numerals and reasons identified as the last result while updating. The drain
is transient presentation, not a real zero, a Rest day or a claimed percentage of
network completion. Never animate unavailable data into an invented score.

A failed sync restores the last valid presentation with an error/stale state.
New missing or partial results use their real unavailable state. Credential
changes clear retained presentation immediately. Repeated pulls share the active
sync; no competing loops. Reduce Motion keeps values steady with a static syncing
label, then changes them directly or by cross-fade.

Haptics mark actions: success when sync completes, light feedback on a dial tap,
and a selection tick on each scrubbed day change. No continuous vibration for
breathing, background motion or a held chart position. Respect system haptic settings.

Sync choreography builds on **the dial**, **big rolling numerals** and **every
number has its reason**. Motion tells the user that data is updating; it never
changes the underlying value or its availability.

## Accessibility and visibility

- Reduce Motion: no breathing and no moving background. No numeric rolling,
  spatial zoom/morph or drain/refill sweeps. Use static states and short cross-fades.
- Reduce Transparency: glass becomes solid surfaceRaised; dense cards remain
  opaque enough to read. A static or moving canvas must not reduce text contrast.
- Both preferences together must retain the complete interaction and all data.
  Observe preference changes live, including while an animation is running.
- Colour is reinforced by the number, human why-line and VoiceOver band/availability text.
  Dynamic Type, VoiceOver focus and native back gestures survive transitions.
- App inactivity, a covered/hidden root and offscreen controls pause their clocks.
  Selecting a different tab does not leave invisible dial animations running.

## Performance and verification

Target 120Hz with no app-caused dropped frames during foreground interaction on a
ProMotion iPhone. At 120Hz the display interval is about 8.33ms. Treat this as a
measured release gate, not a guarantee supplied by a SwiftUI modifier. Respect the
system's adaptive idle rate; do not force a permanent 120Hz background timer.

Before phase 4 sign-off, profile Home with xctrace using Animation Hitches and
SwiftUI/Time Profiler as needed. Use DEBUG offline fixtures with visible Sample
data and existing signing. Record device/OS/build, actual refresh cadence, power/
thermal conditions, missed frame deadlines and hitch counts. A simulator or a
60Hz recording cannot prove the 120Hz target. Current API verification is not a
performance PASS; no Home animation trace exists yet.

Measure launch sweeps/rolling digits, the Body Battery point pulse,
scrolling, dial-to-detail and interrupted return gestures, chart scrubbing, and
sync success/failure/refill. Repeat with Reduce Motion, Reduce Transparency and
both together. Also verify that hidden/inactive views stop producing animation
updates. Keep traces and a concise result report with the screen verification.

Isolate animation state to its surface. Use one static top gradient and native
navigation materials; avoid stacked blur/material passes. Precompute chart and
baseline data; a scrub changes the selected day, not the scoring model. Simplify
an effect until the recorded scenarios meet the frame and legibility targets.

## Creative latitude

New interactive and animated ideas are welcome beyond this list. During phase 4,
propose and build them within the approved screen scope. For every interaction,
state the identity anchor it builds on, the data/state it reveals, its Reduce
Motion and Reduce Transparency forms, and its 120Hz verification result. An idea
without an anchor or an accessible complete form does not belong in Diel.

Possible extensions, to explore during phase 4:

- Tap a why-line to focus its contributing measurement and reference band together.
  Builds on **every number has its reason** and **you against your own baseline**.
  A short focus-light change can connect them; Reduce Motion uses a static outline
  and selected reference text. It does not add another colour or rerun scoring.
- Tap the baseline-learning line to reveal the counted nights and missing gaps in
  its reference window. Builds on **you against your own baseline** and **every
  number has its reason**. Use a legible solid detail surface and a static list or
  grid under Reduce Motion, with no invented progress or new ring component.

These examples are options, not extra work started before the phase 4 gate.

## Verified SDK foundation

The installed iOS27.2 SDK was checked before updating this contract. It contains
MeshGradient with an explicitly pausable animation timeline, native glass/control
and matched-identity APIs, numericText transitions, chart selection/gesture APIs,
selection haptics, refreshable and accessibility preferences. iOS27 additionally
provides crossFade navigation and AnyNavigationTransition for the reduced-motion
navigation path. Glass morphing within a container and matched navigation are
separate mechanisms; verify the composed result in the simulator and on device.

The exact APIs, availability and installed-interface evidence are kept with the
private verification records. Future executor specs must use those verified signatures and recheck the installed
SDK if it changes. No phase 4 code or performance claim is implied by this document.

## Local data and sync

SwiftData keeps Garmin records, computed scores and their versioned evidence.
Screens show saved data before a network refresh starts and continue showing it
through failed or partial refreshes. Incremental sync includes missed days and
revisits the previous three calendar days plus today. Full local history stays
available for causal baselines and Trends.

Sync runs on launch, on foreground return after five minutes, every fifteen
minutes while active, and on pull to refresh. Background refresh requests an
earliest check thirty minutes later. A power-required overnight processing
request performs a fuller catch-up. Settings shows the last successful sync and
the next planned check without promising iOS delivery.

## States

- **Loading:** without a prior valid result, dials show their track and "–".
  Pull-to-sync with prior data uses the separate syncing presentation above.
  No invented zero or spinning score.
- **Empty** (no data yet): one line explaining why, plus one action ("Sync now" or "Add your key").
- **Error:** a single card at the top of Home in `surface`, one short message and a
  retry button. Sync failures use the same copy in Home and Settings:
  "Sync couldn't finish. Your saved data is still here." Never a raw error message.
- **Stale data:** if the last sync is over 12 hours old, show "Updated 14 h ago" in
  secondary text under the dials, at least `.subheadline`.

## Words and density

1. No engineering vocabulary on screen: no EWMA, half-life, reference, series
   points, readings needed, native units, complete collection, date-matched,
   source date or bundled. Say "your normal" and "load".
2. No provenance on screen: no ISO dates, window ranges, reading counts or
   "Garmin · date" stamps. Dates read "Oct 24" or "last night". Calculation
   details live in one "How this is calculated" sheet, opened from an info
   button on each detail screen. Keep the sheet human too; preserve technical
   provenance in the data model and review evidence. The explicitly requested
   60-tick learning figure and matching This week learning line are the only
   count exceptions; they add no eligibility gate.
3. One card = one idea: a headline number, at most one sentence, one visual.
   The requested morning brief has a headline and at most two sentences.
   No label/value lists longer than three rows on Home.
4. No runs of small grey text. Secondary text is `.subheadline` at minimum,
   ideally one line.
5. Under each dial: name and why-line only. Drop the status word, such as
   "Good" or "Complete". Colour follows the score scale; VoiceOver retains the status band.
6. Why-lines are human: "HRV 10% above normal", "Hardest day in 2 weeks",
   "9 min short of need". Use the actual measurement and selected reason.
7. Activities show type, duration and load, never Garmin's raw title.

Short, plain and specific. Numbers before adjectives. No exclamation marks, emoji
or medical claims. Scores are estimates; the Settings disclaimer says so once.
These rules supersede older screen-density and provenance requirements. Missing
and partial states remain honest, and underlying source/date evidence is retained.

### UI review gate

Every UI task's report lists every user-visible string on every affected screen,
including sheets, dialogs, errors, missing states, labels, dates and chart callouts.
The reviewer fails any string that breaks Words and density. Include the reviewed
string inventory with build/test results and simulator screenshots. User review
and physical-device performance gates remain separate.

## Don'ts

- Don't use Whoop's names (Recovery, Strain), its icons, layouts or exact colours.
- Don't turn dense data cards or chart plots into glass controls.
- Don't add decorative colours, card gradients or unrelated light effects.
- Don't let a glow or background hide a number, band, normal range or why-line.
- Keep chart accents within the selected theme's metric colours. Recent nights
  uses each night's closeness to need for its colour; add no decorative accents.
- Don't show a number without its unit, or a score without its reason.
- Don't hard-code a colour, font size, spacing value or radius outside the tokens file.
