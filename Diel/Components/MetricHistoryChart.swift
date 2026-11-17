import Charts
import ScoringKit
import SwiftUI

struct MetricHistoryChart: View {
  @Environment(\.dielTheme) private var theme
  let metric: TodayMetric
  let points: [DayChartPoint]
  var compact = false
  var showsLatestSummary = true
  @State private var selection: Date?
  @State private var dismissal: Task<Void, Never>?
  private var selected: DayChartPoint? {
    guard let selection else { return points.last }
    let date = TodayPresentation.dateKey(selection, calendar: .current)
    return points.first { $0.date == date }
      ?? points.min {
        abs($0.plotDate.timeIntervalSince(selection))
          < abs($1.plotDate.timeIntervalSince(selection))
      }
  }
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
      // The value row keeps its space when a scrub callout leaves, so the card never shifts.
      HStack(alignment: .firstTextBaseline) {
        RollingValue(value: selected?.value)
        Text(selected?.plotDate.formatted(.dateTime.month(.abbreviated).day()) ?? "")
          .dielBodyStyle()
        Spacer()
      }
      .opacity(showsLatestSummary || selection != nil ? 1 : 0)
      .accessibilityHidden(!showsLatestSummary && selection == nil)
      if showsLatestSummary {
        Text(
          compact && selected?.normal == nil
            ? "Learning your normal" : selected?.reason ?? "No reading for this day"
        ).dielBodyStyle()
      }
      Chart {
        ForEach(DayChartPoint.fullWidthNormalBand(in: points)) { point in
          if let normal = point.normal {
            AreaMark(
              x: .value("Day", point.plotDate),
              yStart: .value("Normal low", normal.lowerBound),
              yEnd: .value("Normal high", normal.upperBound)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(theme.colors.surfaceRaised.opacity(DesignTokens.Today.bandOpacity))
          }
        }
        ForEach(points) { point in
          if let value = point.value {
            LineMark(
              x: .value("Day", point.plotDate), y: .value(metric.title, value),
              series: .value("Section", point.segment)
            )
            .foregroundStyle(
              metric == .load ? theme.colors.load : theme.colors.textSecondary
            )
            .lineStyle(StrokeStyle(lineWidth: DesignTokens.Today.traceWidth))
            PointMark(x: .value("Day", point.plotDate), y: .value(metric.title, value))
              .foregroundStyle(
                metric == .load ? theme.colors.load : theme.colors.textSecondary
              )
              .symbolSize(DesignTokens.Today.pointSize)
          }
        }
        if let selected {
          // The rule marks an active touch only; the idle chart keeps just the latest point.
          if selection != nil {
            RuleMark(x: .value("Day", selected.plotDate)).foregroundStyle(
              theme.colors.hairline)
          }
          if let value = selected.value {
            PointMark(x: .value("Day", selected.plotDate), y: .value(metric.title, value))
              .foregroundStyle(
                metric == .load
                  ? theme.colors.load
                  : theme.scoreColor(
                    value: value, band: selected.colour.scoreBand,
                    kind: metric == .sleep ? .sleep : .readiness)
              ).symbolSize(DesignTokens.Today.pointSize)
          }
        }
      }
      .chartYScale(domain: 0...100)
      .chartXScale(
        domain: (points.first?.plotDate ?? Date())...(points.last?.plotDate ?? Date()),
        range: .plotDimension(padding: 0)
      )
      .chartXAxis {
        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
          AxisValueLabel(format: .dateTime.month(.abbreviated).day(), anchor: .top).font(
            .subheadline)
        }
      }
      .chartYAxis {
        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
          AxisGridLine().foregroundStyle(theme.colors.hairline)
          AxisValueLabel(anchor: .trailing).font(.subheadline)
        }
      }
      .chartPlotStyle { plot in plot.clipped() }
      .chartOverlay { proxy in
        GeometryReader { geometry in
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
        }
      }
      .frame(
        height: compact ? DesignTokens.Today.chartHeight : DesignTokens.Today.detailChartHeight
      )
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(metric.title) history")
      .accessibilityValue(
        "\(selected?.plotDate.formatted(.dateTime.month(.abbreviated).day()) ?? ""), \(DialPresentation.number(selected?.value))"
          + (showsLatestSummary ? ". \(selected?.reason ?? "Unavailable")" : "")
      )
      .accessibilityAdjustableAction { direction in
        guard let selected, let index = points.firstIndex(of: selected) else { return }
        let next = direction == .increment ? min(index + 1, points.count - 1) : max(index - 1, 0)
        // VoiceOver keeps its place between adjustments; only touch selections time out.
        dismissal?.cancel()
        selection = points[next].plotDate
      }
      .accessibilityIdentifier("history-chart-\(metric.rawValue)")
      if !compact {
        Text(
          selected?.normal.map {
            "Your normal \(DialPresentation.number($0.lowerBound))–\(DialPresentation.number($0.upperBound))"
          } ?? "Learning your normal"
        ).dielBodyStyle()
      }

    }
    .sensoryFeedback(.selection, trigger: selected?.date) { _, _ in selection != nil }
    .onDisappear {
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

/// Calendar nights stay separate so missing duration or need never becomes zero.
nonisolated struct RecentSleepPoint: Identifiable {
  let date: ScoringDate
  let duration: ScoringKit.ScoringMetric?
  let need: ScoringKit.ScoringMetric?
  var id: ScoringDate { date }
  var plotDate: Date { TodayPresentation.displayDate(date)! }
  var durationHours: Double? { Self.hours(duration) }
  var needHours: Double? { Self.hours(need).flatMap { $0 > 0 ? $0 : nil } }
  var summary: String {
    "Duration \(TodayPresentation.duration(duration)), need \(TodayPresentation.duration(need))"
  }

  /// A complete pair has its own zero baseline; duration alone never implies a deficit.
  var signedMinutes: Double? {
    guard durationHours != nil, needHours != nil,
      let duration = duration?.value, let need = need?.value
    else { return nil }
    return (duration - need) / 60
  }

  var isNearNeed: Bool {
    signedMinutes.map { abs($0) <= DesignTokens.SleepComposition.nearNeedMinutes } ?? false
  }

  /// Presentation colour only. This does not replace Garmin's Sleep Score.
  var closeness: Double? {
    guard let durationHours, let needHours, needHours > 0 else { return nil }
    return max(0, 1 - abs(durationHours - needHours) / needHours) * 100
  }

  func callout(locale: Locale) -> String {
    let weekday = plotDate.formatted(.dateTime.weekday(.abbreviated).locale(locale))
    guard let signedMinutes else {
      if durationHours == nil {
        return duration?.coverage == .partial || duration?.reason == .partial
          ? String(localized: "\(weekday) · Sleep duration partial", locale: locale)
          : String(localized: "\(weekday) · Sleep duration missing", locale: locale)
      }
      return need?.coverage == .partial || need?.reason == .partial
        ? String(localized: "\(weekday) · Sleep need partial", locale: locale)
        : String(localized: "\(weekday) · Sleep need missing", locale: locale)
    }
    if signedMinutes == 0 {
      return String(localized: "\(weekday) · Met need", locale: locale)
    }
    let duration = TodayPresentation.duration(minutes: Int(abs(signedMinutes).rounded()))
    return signedMinutes < 0
      ? String(localized: "\(weekday) · \(duration) short", locale: locale)
      : String(localized: "\(weekday) · \(duration) extra", locale: locale)
  }

  static func points(day: ScoredDay, history: [ScoredDay]) -> [Self] {
    let days = Dictionary(grouping: history.filter { $0.input.date != day.input.date } + [day]) {
      $0.input.date
    }
    return (0..<7).reversed().compactMap { offset in
      guard let date = day.input.date.adding(days: -offset) else { return nil }
      let matches = days[date] ?? []
      let input = matches.count == 1 ? matches.first?.input : nil
      return Self(date: date, duration: input?.sleepSeconds, need: input?.sleepNeedSeconds)
    }
  }

  private static func hours(_ metric: ScoringKit.ScoringMetric?) -> Double? {
    guard let metric, metric.coverage == .complete, metric.reason == nil,
      let seconds = metric.value, seconds.isFinite, seconds >= 0
    else { return nil }
    return seconds / 3600
  }
}

/// Both sides share minutes per point, while each side fits its own observed extent.
nonisolated struct RecentSleepScale {
  let lower: Double
  let upper: Double
  let hasExtra: Bool

  init(points: [RecentSleepPoint]) {
    let minutes = points.compactMap(\.signedMinutes)
    let minimum = minutes.min() ?? 0
    let maximum = minutes.max() ?? 0
    let padding = DesignTokens.SleepComposition.minimumHistoryHeadroomMinutes
    lower = min(-padding, minimum * DesignTokens.SleepComposition.historyRangeHeadroom)
    upper = max(padding, maximum * DesignTokens.SleepComposition.historyRangeHeadroom)
    hasExtra = maximum > DesignTokens.SleepComposition.nearNeedMinutes
  }

  var baselineFraction: Double { upper / (upper - lower) }
  func fraction(for minutes: Double) -> Double { minutes / (upper - lower) }
}

struct RecentSleepChart: View {
  @Environment(\.dielTheme) private var theme
  @Environment(\.locale) private var locale
  private let points: [RecentSleepPoint]
  @State private var selection: ScoringDate?
  @State private var dismissal: Task<Void, Never>?

  init(points: [RecentSleepPoint], scale: RecentSleepScale) {
    self.points = points
    self.scale = scale
  }

  private var selected: RecentSleepPoint? {
    points.first { $0.date == selection }
  }

  private let scale: RecentSleepScale

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      Text("Recent nights").font(.headline)
      // Reserve one line so selecting a night does not move the plot under the finger.
      ZStack(alignment: .leading) {
        Text(" ").hidden()
        if let selected {
          Text(selected.callout(locale: locale))
            .accessibilityIdentifier("recent-sleep-selection")
        }
      }
      .dielBodyStyle()
      .monospacedDigit()
      .accessibilityHidden(true)
      VStack(spacing: DesignTokens.Spacing.s8) {
        GeometryReader { geometry in
          ZStack {
            Path { path in
              path.move(
                to: CGPoint(
                  x: 0,
                  y: DesignTokens.Spacing.s4
                    + (geometry.size.height - DesignTokens.Spacing.s8) * scale.baselineFraction))
              path.addLine(
                to: CGPoint(
                  x: geometry.size.width,
                  y: DesignTokens.Spacing.s4
                    + (geometry.size.height - DesignTokens.Spacing.s8) * scale.baselineFraction))
            }
            .stroke(theme.colors.hairline, lineWidth: DesignTokens.Today.cursorWidth)
            HStack(spacing: 0) {
              ForEach(points) { point in
                RecentSleepBar(
                  point: point, scale: scale, selected: point.date == selection
                )
                .frame(maxWidth: .infinity)
              }
            }
          }
          .contentShape(.rect)
          .gesture(
            HorizontalScrubGesture { location in
              select(at: location, width: geometry.size.width)
            }
          )
          .onTapGesture(coordinateSpace: .local) { location in
            select(at: location, width: geometry.size.width)
          }
        }
        .frame(
          height: scale.hasExtra
            ? DesignTokens.Today.chartHeight : DesignTokens.SleepComposition.shortHistoryHeight)
        HStack(spacing: 0) {
          ForEach(points) { point in
            Text(point.plotDate, format: .dateTime.weekday(.narrow))
              .frame(maxWidth: .infinity)
          }
        }
        .dielBodyStyle()
        .accessibilityHidden(true)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Recent sleep duration and need")
      .accessibilityValue(
        selected.map {
          "\($0.plotDate.formatted(.dateTime.month(.abbreviated).day().locale(locale))), \($0.callout(locale: locale)). \($0.summary)"
        } ?? "Seven nights. Adjust to hear each night."
      )
      .accessibilityAdjustableAction { direction in
        let index = points.firstIndex { $0.date == selection }
        let next: Int
        if direction == .increment {
          next = min((index ?? -1) + 1, points.count - 1)
        } else {
          next = max((index ?? points.count) - 1, 0)
        }
        if points.indices.contains(next) { select(points[next]) }
      }
      .accessibilityIdentifier("recent-sleep-chart")
    }
    .sensoryFeedback(.selection, trigger: selection) { _, new in new != nil }
    .onChange(of: points.map(\.date)) { _, _ in resetSelection() }
    .onDisappear { resetSelection() }
  }

  private func resetSelection() {
    selection = nil
    dismissal?.cancel()
    dismissal = nil
  }

  private func select(_ point: RecentSleepPoint) {
    selection = point.date
    dismissal?.cancel()
    dismissal = Task {
      do {
        try await Task.sleep(for: .seconds(DesignTokens.SleepComposition.historySelectionDuration))
        guard !Task.isCancelled else { return }
        selection = nil
      } catch {}
    }
  }

  private func select(at location: CGPoint, width: CGFloat) {
    guard width > 0, !points.isEmpty else { return }
    let fraction = min(max(location.x / width, 0), 1)
    let index = min(Int(fraction * Double(points.count)), points.count - 1)
    select(points[index])
  }
}

private struct RecentSleepBar: View {
  @Environment(\.dielTheme) private var theme
  let point: RecentSleepPoint
  let scale: RecentSleepScale
  let selected: Bool

  var body: some View {
    GeometryReader { geometry in
      let plotHeight = geometry.size.height - DesignTokens.Spacing.s8
      let center = DesignTokens.Spacing.s4 + plotHeight * scale.baselineFraction
      let width = geometry.size.width * DesignTokens.SleepComposition.historyBarWidthFraction
      if let minutes = point.signedMinutes {
        let height = abs(scale.fraction(for: minutes)) * plotHeight
        let color = theme.scoreColor(value: point.closeness, kind: .sleep)
        if point.isNearNeed {
          Circle()
            .fill(color)
            .overlay {
              if selected {
                Circle().strokeBorder(
                  theme.colors.textPrimary, lineWidth: DesignTokens.Today.selectedStroke)
              }
            }
            .frame(width: DesignTokens.Spacing.s8, height: DesignTokens.Spacing.s8)
            .position(x: geometry.size.width / 2, y: center)
        } else {
          RoundedRectangle(cornerRadius: DesignTokens.Spacing.s4)
            .fill(color)
            .overlay {
              if selected {
                RoundedRectangle(cornerRadius: DesignTokens.Spacing.s4)
                  .strokeBorder(
                    theme.colors.textPrimary, lineWidth: DesignTokens.Today.selectedStroke)
              }
            }
            .frame(width: width, height: height)
            .position(x: geometry.size.width / 2, y: center - (minutes < 0 ? -height : height) / 2)
        }
      } else {
        Circle()
          .fill(theme.colors.textTertiary.opacity(DesignTokens.Today.pointOpacity))
          .frame(width: DesignTokens.Spacing.s4, height: DesignTokens.Spacing.s4)
          .position(x: geometry.size.width / 2, y: center)
      }
    }
    .accessibilityHidden(true)
  }
}
