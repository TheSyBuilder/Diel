import ScoringKit
import SwiftUI

nonisolated enum TodayDestination: Hashable {
  case metric(TodayMetric)
  case bodyBattery
  case trends
}

struct TodayDetailView: View {
  @Environment(\.dielTheme) private var theme
  let metric: TodayMetric
  let snapshot: TodaySnapshot
  var active = true
  @State private var showingCalculation = false
  private var presentation: TodayPresentation { snapshot.presentation }
  private var highlights: TodayHighlights { snapshot.highlights }
  private var dial: TodayDial { presentation.dials.first { $0.metric == metric }! }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
        DetailHero(dial: dial)
        if metric == .readiness {
          Text("Diel estimate").dielBodyStyle()
          let learning = snapshot.learning
          if learning.isLearning {
            ReadinessLearningFigure(
              evidence: learning, active: active && !showingCalculation)
          }
          DetailMeasurementRows(
            rows: snapshot.readinessRows,
            heroReason: dial.reason)
        } else if metric == .sleep {
          LastNightSummary(highlights: highlights)
        } else {
          ActivityCardContent(
            highlights: highlights, load: dial, showAll: true, showsLoadSummary: false)
        }
        if metric == .sleep {
          RecentSleepChart(points: snapshot.recentSleep, scale: snapshot.recentSleepScale)
        } else {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
            Text("Past month").font(.headline)
            MetricHistoryChart(
              metric: metric,
              points: snapshot.month[metric] ?? [],
              showsLatestSummary: false)
          }
        }
      }
      .padding(DesignTokens.Spacing.screenMargin)
    }
    .dielTabScrollClearance()
    .accessibilityIdentifier("detail-scroll")
    .background(theme.colors.canvas)
    .navigationTitle(metric.title)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      SampleDataToolbar()
      ToolbarItem(placement: .topBarTrailing) {
        Button("How this is calculated", systemImage: "info.circle") { showingCalculation = true }
          .labelStyle(.iconOnly).accessibilityIdentifier("calculation-info")
      }
    }
    .sheet(isPresented: $showingCalculation) { CalculationSheet(topic: metric.title) }
    .accessibilityIdentifier("detail-\(metric.rawValue)")
  }
}

struct DetailHero: View {
  @Environment(\.dielTheme) private var theme
  let dial: TodayDial
  var body: some View {
    VStack(spacing: DesignTokens.Spacing.s16) {
      ZStack {
        DialRing(
          progress: dial.progress ?? 0, scale: dial.ringScale, tint: theme.dialColor(dial))
        Text(dial.number).dielHeroNumberStyle()
          .foregroundStyle(theme.colors.textPrimary)
      }.frame(width: DesignTokens.Today.heroDiameter, height: DesignTokens.Today.heroDiameter)
      Text(dial.reason).font(.headline).multilineTextAlignment(.center)
    }.frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(dial.accessibilityLabel)
  }
}

struct DetailMeasurementRows: View {
  @Environment(\.dielTheme) private var theme
  let rows: [TodayEvidenceRow]
  let heroReason: String
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
          HStack(alignment: .firstTextBaseline) {
            HStack(spacing: DesignTokens.Spacing.s8) {
              if row.id == "latest-hrv" || row.id == "hrv-trend" { DielSymbolView(.hrv) }
              Text(row.label)
            }.font(.subheadline)
            Spacer(minLength: DesignTokens.Spacing.s8)
            Text(row.value).font(.headline).monospacedDigit().multilineTextAlignment(.trailing)
          }
          if !row.detail.isEmpty && row.detail != heroReason {
            Text(row.detail).dielBodyStyle()
          }
        }.accessibilityElement(children: .combine).accessibilityIdentifier(
          "detail-evidence-\(row.id)")
      }
    }.padding(DesignTokens.Spacing.cardPadding)
      .background(
        theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
  }
}

struct BodyBatteryDetailView: View {
  @Environment(\.dielTheme) private var theme
  let days: [BodyBatteryDay]
  let initialDate: ScoringDate
  let now: Date
  let active: Bool
  @State private var selectedDate: ScoringDate?
  @State private var showingCalculation = false
  private var selected: BodyBatteryDay? {
    days.first { $0.date == (selectedDate ?? initialDate) } ?? days.last
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
        if let selected {
          Text(selected.start, format: .dateTime.weekday(.wide).month(.abbreviated).day())
            .dielSectionLabelStyle().accessibilityIdentifier("body-battery-day")
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
            BodyBatteryCardContent(
              samples: selected.samples, active: active && !showingCalculation,
              day: selected, now: now, detail: true
            )
            .id(selected.date)
            BodyBatteryDailySummary(
              day: selected, now: now, isToday: now >= selected.start && now < selected.end)
          }
          .padding(DesignTokens.Spacing.cardPadding)
          .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
        }
        BodyBatteryWakeWeek(days: days, now: now, selection: selected?.date) { selectedDate = $0 }
      }.padding(DesignTokens.Spacing.screenMargin)
    }.dielTabScrollClearance()
      .accessibilityIdentifier("body-battery-detail-scroll")
      .background(theme.colors.canvas)
      .navigationTitle("Body Battery").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        SampleDataToolbar()
        ToolbarItem(placement: .topBarTrailing) {
          Button("How this is calculated", systemImage: "info.circle") { showingCalculation = true }
            .labelStyle(.iconOnly).accessibilityIdentifier("calculation-info")
        }
      }
      .sheet(isPresented: $showingCalculation) { CalculationSheet(topic: "Body Battery") }
      .sensoryFeedback(.selection, trigger: selectedDate)
  }
}

private struct BodyBatteryDailySummary: View {
  let day: BodyBatteryDay
  let now: Date
  let isToday: Bool
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      ViewThatFits(in: .horizontal) {
        HStack(spacing: DesignTokens.Spacing.s16) {
          Text(day.charged.map { "Charged +\($0) overnight" } ?? "Charge unavailable")
          Text(
            day.drained.map { "Drained −\($0)\(isToday ? " so far" : "")" } ?? "Drain unavailable")
        }
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
          Text(day.charged.map { "Charged +\($0) overnight" } ?? "Charge unavailable")
          Text(
            day.drained.map { "Drained −\($0)\(isToday ? " so far" : "")" } ?? "Drain unavailable")
        }
      }
      HStack(spacing: DesignTokens.Spacing.s16) {
        Text(day.high(through: now).map { "High \($0)" } ?? "High unavailable")
        Text(day.low(through: now).map { "Low \($0)" } ?? "Low unavailable")
      }
    }.dielBodyStyle().monospacedDigit()
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("body-battery-daily-summary")
  }
}

private struct BodyBatteryWakeWeek: View {
  @Environment(\.dielTheme) private var theme
  let days: [BodyBatteryDay]
  let now: Date
  let selection: ScoringDate?
  let select: (ScoringDate) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
      Text("At wake-up").font(.headline)
      HStack(alignment: .bottom, spacing: DesignTokens.Spacing.s8) {
        ForEach(days) { day in
          Button {
            select(day.date)
          } label: {
            VStack(spacing: DesignTokens.Spacing.s8) {
              Text(day.wake(through: now).map { "\($0.value)" } ?? "–")
                .font(.subheadline.weight(.semibold)).monospacedDigit()
              GeometryReader { geometry in
                VStack {
                  Spacer(minLength: 0)
                  RoundedRectangle(cornerRadius: DesignTokens.Spacing.s4)
                    .fill(
                      day.date == selection ? theme.colors.textPrimary : theme.colors.textSecondary
                    )
                    .frame(
                      height: day.wake(through: now).map {
                        max(DesignTokens.Spacing.s4, geometry.size.height * Double($0.value) / 100)
                      } ?? DesignTokens.Spacing.s4
                    )
                    .opacity(
                      day.wake(through: now) == nil ? DesignTokens.Today.batteryFillOpacity : 1)
                }
              }.frame(height: DesignTokens.Today.batteryWakeBarHeight)
              Text(day.start, format: .dateTime.weekday(.narrow))
                .font(.subheadline)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(DesignTokens.Spacing.s4)
            .frame(maxWidth: .infinity)
            .background(
              day.date == selection ? theme.colors.surfaceRaised : theme.colors.surface,
              in: .rect(cornerRadius: DesignTokens.Spacing.s8)
            )
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(day.start.formatted(.dateTime.month(.abbreviated).day())), wake-up Body Battery \(day.wake(through: now).map { String($0.value) } ?? "unavailable")"
          )
          .accessibilityHint("Shows this day")
          .accessibilityAddTraits(day.date == selection ? .isSelected : [])
          .accessibilityIdentifier("body-battery-day-\(day.date.rawValue)")
        }
      }
    }
    .padding(DesignTokens.Spacing.cardPadding)
    .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
    .accessibilityIdentifier("body-battery-wake-week")
  }
}

struct CalculationSheet: View {
  @Environment(\.dielTheme) private var theme
  let topic: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
          Text(topic).font(.title2.bold())
          switch topic {
          case "Readiness":
            Text(
              "Diel compares your heart rate variability and daily resting heart rate with your own normal, then adds how your sleep compares with your need."
            )
            Text(
              "Your recent pattern matters more than older nights. Last night's HRV and today's resting heart rate also count separately, so a trend cannot hide a missing measurement."
            )
            Text(
              "HRV contributes 50%, resting heart rate 25%, and sleep 25%. Sleep includes last night and the last three nights. Extra sleep can offset a short night."
            )
            Text(
              "The result is kept between 5 and 95."
            )
            Text(
              "The learning ring shows the last 60 days, ending on this day. A bright tick means both HRV and daily resting heart rate were fully recorded; gaps stay dim. The count describes your history, not a target needed for a score."
            )
          case "Sleep":
            Text(
              "The dial shows Garmin Sleep Score, supplied by Garmin. Duration and sleep need remain separate from the score and do not replace a missing score."
            )
            Text(
              "The middle line is each night's sleep need. Bars rise for extra minutes and fall for minutes short. A coloured dot means within five minutes of need; a faint dot means duration or need is missing or partial."
            )
            Text(
              "The stage bar shows total time in Deep, REM, Light and Awake, not when those stages happened. Short stages keep a visible width; touch the bar for their recorded totals."
            )
          case "Load":
            Text(
              "Diel Load accumulates effort from your all-day heart rate, including movement outside workouts. It runs from 0 to 100; the ring shows the same fraction."
            )
            Text(
              "Each recorded interval contributes Banister TRIMP using heart rate reserve above the same day's resting heart rate. Intervals stop at five minutes so gaps cannot fill the day. Load is 100 × (1 − exp(−TRIMP / 500)), rounded to a whole number."
            )
            Text(
              "Maximum heart rate is the highest supported pair of readings in the causal 90-day history, including this day so far. A pair must be within five minutes and ten bpm; an isolated spike cannot set the maximum. This observed maximum is an estimate, not a measured physiological limit."
            )
            Text(
              "Usual Load is the prior 28-day median by the same time when enough recorded coverage exists, otherwise the median of complete days. Today's Load never falls after refresh; an earlier value is retained if revised readings lower the estimate."
            )
            Text(
              "No recorded heart rate means unavailable. Before resting heart rate, a reliable maximum or an interval is available, zero means no calculable effort yet. Activity rows keep Garmin's separate workout load."
            )
            Text(
              "Active minutes adds moderate and vigorous minutes once each. It describes time, rather than Garmin's doubled credit toward an intensity goal."
            )
          default:
            Text(
              "Garmin estimates Body Battery from your body's signals throughout the day. Diel displays Garmin's values without grading them."
            )
            Text(
              "The chart spans midnight to midnight. Only recorded values appear; future hours and gaps stay empty. Touch the chart for the closest recorded time."
            )
            Text(
              "Charged and drained are Garmin's daily totals, not changes calculated from the curve. High and low use Garmin's daily values when available, otherwise the recorded points."
            )
            Text(
              "Wake-up bars use the closest Body Battery value within 15 minutes of your recorded sleep end. A dash means the wake time or a nearby value is missing. Tap a day to see it above."
            )
          }
          Text(
            "History charts compare each day with your usual range from earlier days. The shaded range appears once enough history is available and never uses future days."
          )
        }.font(.body).foregroundStyle(theme.colors.textSecondary)
          .padding(DesignTokens.Spacing.screenMargin)
      }.background(theme.colors.surface)
        .navigationTitle("How this is calculated").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }.accessibilityIdentifier("calculation-sheet")
  }
}
