import Charts
import ScoringKit
import SwiftUI

struct TodayCard<Content: View>: View {
  @Environment(\.dielTheme) private var theme
  let title: String
  var symbol: DielSymbol? = nil
  var open: (() -> Void)? = nil
  @ViewBuilder let content: () -> Content
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var pressed = false

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
      if let open {
        Button(action: open) {
          header
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
      } else {
        header
      }
      content()
    }
    .padding(DesignTokens.Spacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      pressed ? theme.colors.surfaceRaised : theme.colors.surface,
      in: .rect(cornerRadius: DesignTokens.Shape.cardRadius)
    )
    .contentShape(.rect(cornerRadius: DesignTokens.Shape.cardRadius))
    .modifier(TodayCardInteraction(open: open, pressed: $pressed))
    .scaleEffect(reduceMotion || !pressed ? 1 : DesignTokens.Today.pressScale)
    .animation(
      reduceMotion ? nil : .spring(duration: DesignTokens.Today.interactionDuration), value: pressed
    )
    .modifier(CardScrollAppearance())
    .accessibilityElement(children: .contain)
  }

  private var header: some View {
    HStack(spacing: DesignTokens.Spacing.s8) {
      if let symbol {
        DielSymbolView(symbol)
          .font(.headline)
          .foregroundStyle(theme.colors.textSecondary)
      }
      Text(title).font(.headline)
      Spacer()
      if open != nil {
        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold))
          .foregroundStyle(theme.colors.textSecondary)
      }
    }
    .contentShape(.rect)
  }

}

private struct TodayCardInteraction: ViewModifier {
  let open: (() -> Void)?
  @Binding var pressed: Bool

  func body(content: Content) -> some View {
    if let open {
      content
        .onTapGesture(perform: open)
        .gesture(CardPressGesture { pressed = $0 })
    } else {
      content
    }
  }
}

private struct CardScrollAppearance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func body(content: Content) -> some View {
    let motionReduced = reduceMotion
    let rise = DesignTokens.Today.scrollRise
    let faded = DesignTokens.Today.scrollOpacity
    content.scrollTransition(.interactive, axis: .vertical) { view, phase in
      view.opacity(motionReduced || phase.isIdentity ? 1 : faded)
        .offset(y: motionReduced || phase.isIdentity ? 0 : rise)
    }
  }
}

struct RollingValue: View {
  @Environment(\.dielTheme) private var theme
  let value: Double?
  var suffix = ""
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Text(value.map { $0.formatted(.number.precision(.fractionLength(0))) + suffix } ?? "–")
      .font(DesignTokens.Today.cardNumber).monospacedDigit()
      .foregroundStyle(theme.colors.textPrimary)
      .contentTransition(reduceMotion ? .identity : .numericText(value: value ?? 0))
      .animation(
        reduceMotion ? nil : .smooth(duration: DesignTokens.Today.sweepDuration), value: value)
  }
}

struct LastNightCardContent: View {
  let highlights: TodayHighlights
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    if highlights.awaitingNight {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
        Text("No sleep data yet").font(DesignTokens.Today.cardHeadline)
        Text("Sync your band in Garmin Connect, then pull to refresh.").dielBodyStyle()
      }
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("last-night-waiting")
    } else {
      recorded
    }
  }

  private var recorded: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      Text(highlights.sleepDuration).font(.largeTitle.weight(.semibold)).monospacedDigit()
        .accessibilityIdentifier("last-night-duration")
        .contentTransition(
          reduceMotion ? .identity : .numericText(value: highlights.sleepSeconds ?? 0)
        )
        .animation(
          reduceMotion ? nil : .smooth(duration: DesignTokens.Today.sweepDuration),
          value: highlights.sleepSeconds)
      SleepStageComposition(stages: highlights.stages, compact: true)
      SleepWindowTimes(window: highlights.sleepWindow)
    }
  }
}

struct SleepStageTotals: View {
  @Environment(\.dielTheme) private var theme
  let stages: [SleepStageTotal]

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      ForEach(SleepStage.compositionOrder) { stage in
        HStack(spacing: DesignTokens.Spacing.s8) {
          Circle().fill(theme.colors.sleepStage(stage))
            .frame(width: DesignTokens.Spacing.s8, height: DesignTokens.Spacing.s8)
          Text(stage.title)
          Spacer()
          Text(stages.first { $0.stage == stage }?.duration ?? "Unavailable")
            .monospacedDigit()
        }
        .dielBodyStyle()
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sleep-stage-total-\(stage.rawValue)")
      }
    }
  }
}

struct ActivityCardContent: View {
  let highlights: TodayHighlights
  let load: TodayDial
  var showAll = false
  var showsLoadSummary = true
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
      HStack(alignment: .top, spacing: DesignTokens.Spacing.s16) {
        ActivityNumber(value: highlights.steps.map(Double.init), title: "Steps")
        ActivityNumber(
          value: highlights.activeMinutes.map(Double.init), title: "Active time", isDuration: true)
        if showsLoadSummary {
          ActivityNumber(value: highlights.activeCalories.map(Double.init), title: "Active kcal")
        }
      }
      if highlights.activities.isEmpty {
        Text("No activity details yet").dielBodyStyle()
      } else {
        ForEach(showAll ? highlights.activities : Array(highlights.activities.prefix(3))) {
          activity in
          ActivitySummaryRow(activity: activity)
        }
        if !showAll && highlights.activities.count > 3 {
          Text("More activities").dielBodyStyle()
        }
      }
    }
  }
}

private struct ActivityNumber: View {
  let value: Double?
  let title: String
  var isDuration = false
  @Environment(\.dielTheme) private var theme
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
      if isDuration {
        Text(value.map { TodayPresentation.duration(minutes: Int($0)) } ?? "–")
          .font(DesignTokens.Today.cardNumber).monospacedDigit()
          .foregroundStyle(theme.colors.textPrimary)
      } else {
        RollingValue(value: value)
      }
      Text(title).dielBodyStyle()
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct ActivitySummaryRow: View {
  @Environment(\.dielTheme) private var theme
  let activity: TodayActivity
  var body: some View {
    HStack(spacing: DesignTokens.Spacing.s12) {
      Image(systemName: activity.icon).font(.title2).foregroundStyle(theme.colors.load)
        .accessibilityHidden(true)
      Text(activity.title).font(.subheadline.weight(.semibold))
      Spacer(minLength: DesignTokens.Spacing.s4)
      Text(activity.duration).font(.subheadline).monospacedDigit()
      if let load = activity.load {
        Text("\(DialPresentation.number(load)) load").dielBodyStyle().monospacedDigit()
      }
    }.accessibilityElement(children: .combine)
  }
}

struct BodyBatteryCardContent: View {
  @Environment(\.dielTheme) private var theme
  let samples: [BatterySample]
  let active: Bool
  var day: BodyBatteryDay? = nil
  var now = Date()
  var detail = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var selection: Date?
  @State private var dismissal: Task<Void, Never>?
  @State private var visible = false
  private var visibleSamples: [BatterySample] {
    day?.samples(through: now) ?? samples.filter { $0.date <= now }
  }
  /// The touched reading. Its rule and point appear only while scrubbing and the short hold after.
  private var scrubbed: BatterySample? {
    selection.flatMap { BatterySample.nearest(to: $0, in: visibleSamples) }
  }
  private var selected: BatterySample? { scrubbed ?? visibleSamples.last }
  /// A reading with no neighbour in its section is a point; an area of one would be a sliver.
  private var isolatedSamples: [BatterySample] { BatterySample.isolated(visibleSamples) }
  private var tracedSamples: [BatterySample] {
    let isolated = Set(isolatedSamples.map(\.id))
    return visibleSamples.filter { !isolated.contains($0.id) }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
      HStack(alignment: .firstTextBaseline) {
        RollingValue(value: selected.map { Double($0.value) })
          .accessibilityIdentifier("body-battery-value")
        if let selected {
          Text("at \(selected.date.formatted(date: .omitted, time: .shortened))")
            .dielBodyStyle()
            .accessibilityIdentifier("body-battery-time")
        }
        Spacer()
      }
      if visibleSamples.isEmpty {
        Text("No Body Battery values yet").dielBodyStyle()
      }
      if BatterySample.canShowCurve(visibleSamples) || detail {
        Chart {
          ForEach(tracedSamples) { sample in
            AreaMark(
              x: .value("Time", sample.date),
              yStart: .value("Body Battery baseline", 0),
              yEnd: .value("Body Battery", sample.value),
              series: .value("Section", sample.segment)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(
              LinearGradient(
                colors: [
                  theme.colors.textSecondary.opacity(
                    reduceTransparency
                      ? DesignTokens.Today.batterySolidFillOpacity
                      : DesignTokens.Today.batteryFillOpacity),
                  theme.colors.textSecondary.opacity(
                    reduceTransparency ? DesignTokens.Today.batterySolidFillOpacity : 0),
                ], startPoint: .top, endPoint: .bottom))
            LineMark(
              x: .value("Time", sample.date), y: .value("Body Battery", sample.value),
              series: .value("Section", sample.segment)
            )
            // Monotone cubic interpolation stays within each pair of accepted 0...100 values.
            .interpolationMethod(.monotone)
            .foregroundStyle(theme.colors.textSecondary)
            .lineStyle(StrokeStyle(lineWidth: DesignTokens.Today.traceWidth))
          }
          ForEach(isolatedSamples) { sample in
            PointMark(x: .value("Time", sample.date), y: .value("Body Battery", sample.value))
              .foregroundStyle(theme.colors.textSecondary).symbolSize(
                DesignTokens.Today.pointSize)
          }
          if let day, now >= day.start, now < day.end {
            RuleMark(x: .value("Now", now))
              .foregroundStyle(theme.colors.textTertiary)
              .lineStyle(
                StrokeStyle(
                  lineWidth: DesignTokens.Today.cursorWidth, dash: [DesignTokens.Spacing.s4])
              )
          }
          if let last = visibleSamples.last {
            PointMark(x: .value("Time", last.date), y: .value("Body Battery", last.value))
              .foregroundStyle(theme.colors.textPrimary).symbolSize(DesignTokens.Today.pointSize)
          }
          if let scrubbed {
            RuleMark(x: .value("Time", scrubbed.date))
              .foregroundStyle(theme.colors.hairline)
            PointMark(x: .value("Time", scrubbed.date), y: .value("Body Battery", scrubbed.value))
              .foregroundStyle(theme.colors.textPrimary).symbolSize(
                DesignTokens.Today.pointSize)
          }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(
          domain: day.map { $0.start...$0.end }
            ?? (visibleSamples.first?.date ?? now)...(visibleSamples.last?.date ?? now)
        )
        .chartPlotStyle { plot in plot.clipped() }
        .chartXAxis {
          AxisMarks(values: day.map { [$0.start, $0.midday, $0.end] } ?? []) { value in
            AxisValueLabel(
              anchor: value.index == 0 ? .topLeading : value.index == 2 ? .topTrailing : .top
            ) {
              if let date = value.as(Date.self) {
                Text(date, format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
              }
            }.font(.subheadline)
          }
        }
        .chartYAxis {
          AxisMarks(values: [0, 50, 100]) { _ in
            AxisGridLine().foregroundStyle(theme.colors.hairline)
            AxisValueLabel(anchor: .trailing).font(.subheadline)
          }
        }
        .chartOverlay { proxy in
          GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
              Rectangle().fill(.clear).contentShape(.rect)
                .gesture(
                  HorizontalScrubGesture { location in
                    select(at: location, proxy: proxy, geometry: geometry)
                  } ended: {
                    scheduleDismissal()
                  }
                )
                .onTapGesture(coordinateSpace: .local) { location in
                  select(at: location, proxy: proxy, geometry: geometry)
                  scheduleDismissal()
                }
              // At the largest text sizes the label cannot fit between gridlines and hour
              // labels; the dashed rule alone marks now, and VoiceOver still reads it.
              if typeSize < .accessibility4, let day, now >= day.start, now < day.end,
                let frame = proxy.plotFrame, let x = proxy.position(forX: now),
                let y = proxy.position(
                  forY: BatterySample.nowLabelLevel(latest: visibleSamples.last))
              {
                let plot = geometry[frame]
                let onTrailingHalf = x > plot.width / 2
                // Centred between gridlines, so it never meets the 0, 50 or 100 labels.
                HStack(spacing: 0) {
                  if onTrailingHalf { Spacer(minLength: 0) }
                  Text("Now").dielBodyStyle().fixedSize()
                    .padding(DesignTokens.Spacing.s4)
                    .background(theme.colors.surface)
                  if !onTrailingHalf { Spacer(minLength: 0) }
                }
                .frame(width: onTrailingHalf ? x : plot.width - x)
                .position(
                  x: plot.minX + (onTrailingHalf ? x / 2 : (x + plot.width) / 2),
                  y: plot.minY + y
                )
                .allowsHitTesting(false).accessibilityHidden(true)
              }
              if let last = visibleSamples.last, let frame = proxy.plotFrame,
                let x = proxy.position(forX: last.date), let y = proxy.position(forY: last.value)
              {
                TodayMotion(
                  running: active && visible && !reduceMotion, cycle: DesignTokens.Today.breathCycle
                ) { phase in
                  Circle().fill(
                    theme.colors.textPrimary.opacity(DesignTokens.Today.pointOpacity)
                  )
                  .frame(width: DesignTokens.Spacing.s12, height: DesignTokens.Spacing.s12)
                  .scaleEffect(reduceMotion ? 1 : 1 + phase * (DesignTokens.Today.pulseScale - 1))
                }.position(x: geometry[frame].minX + x, y: geometry[frame].minY + y)
                  .allowsHitTesting(false).accessibilityHidden(true)
              }
            }
          }
        }
        .frame(
          height: detail ? DesignTokens.Today.detailChartHeight : DesignTokens.Today.chartHeight
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body Battery over the day")
        .accessibilityValue(
          (selected.map { "\($0.value), \($0.date.formatted(.dateTime.hour().minute()))" }
            ?? "Unavailable")
            + (day.map { now >= $0.start && now < $0.end } == true
              ? ". Now \(now.formatted(.dateTime.hour().minute()))" : "")
        )
        .accessibilityAdjustableAction { direction in
          guard let selected, let index = visibleSamples.firstIndex(of: selected) else { return }
          let next =
            direction == .increment ? min(index + 1, visibleSamples.count - 1) : max(index - 1, 0)
          // VoiceOver keeps its place between adjustments; only touch selections time out.
          dismissal?.cancel()
          selection = visibleSamples[next].date
        }
        .accessibilityIdentifier("body-battery-chart")
      }
    }
    .sensoryFeedback(.selection, trigger: selected?.date) { _, _ in selection != nil }
    .onScrollVisibilityChange(threshold: DesignTokens.Today.visibilityThreshold) { visible = $0 }
    .onAppear { visible = true }
    .onDisappear {
      visible = false
      dismissal?.cancel()
      selection = nil
    }
  }

  private func select(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
    guard let frame = proxy.plotFrame else { return }
    let plot = geometry[frame]
    let x = min(max(location.x - plot.minX, 0), plot.width)
    dismissal?.cancel()
    if let date = proxy.value(atX: x, as: Date.self) { selection = date }
  }

  private func scheduleDismissal() {
    dismissal?.cancel()
    dismissal = Task {
      try? await Task.sleep(for: .seconds(DesignTokens.Today.selectionHold))
      guard !Task.isCancelled else { return }
      selection = nil
    }
  }
}
