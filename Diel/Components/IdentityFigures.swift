import ScoringKit
import SwiftUI

/// Calendar evidence accompanies the score; it never changes score eligibility.
struct ReadinessLearningFigure: View {
  @Environment(\.dielTheme) private var theme
  let evidence: ReadinessLearningHistory
  let active: Bool
  @Environment(\.dielSampleReferenceDate) private var sampleReferenceDate
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var diameter =
    DesignTokens.IdentityFigures.learningDiameter
  @State private var visible = false
  @State private var currentTime = Date()
  @State private var clockAdjustment = 0

  private var today: ScoringDate? {
    TodayPresentation.selectedDate(
      now: currentTime, calendar: .current, sampleReference: sampleReferenceDate,
      override: nil, available: [])
  }

  private var clockActive: Bool {
    active && visible && scenePhase == .active && sampleReferenceDate == nil
  }

  private var pulses: Bool {
    active && visible && scenePhase == .active && !reduceMotion && evidence.pulses(on: today)
  }

  var body: some View {
    VStack(spacing: DesignTokens.Spacing.s16) {
      ZStack {
        Canvas { context, size in
          for (index, tick) in evidence.ticks.enumerated() {
            let path = LearningTick(index: index, count: evidence.ticks.count)
              .path(in: CGRect(origin: .zero, size: size))
            context.stroke(
              path,
              with: .color(
                tick.complete ? theme.colors.textPrimary : theme.colors.hairline),
              style: StrokeStyle(
                lineWidth: DesignTokens.IdentityFigures.learningTickWidth, lineCap: .round))
          }
        }
        if evidence.pulses(on: today) {
          TodayMotion(running: pulses, cycle: DesignTokens.Today.breathCycle) { phase in
            LearningTick(index: evidence.ticks.count - 1, count: evidence.ticks.count)
              .stroke(
                theme.colors.textPrimary,
                style: StrokeStyle(
                  lineWidth: DesignTokens.IdentityFigures.learningTickWidth, lineCap: .round)
              )
              .shadow(
                color: theme.colors.textPrimary.opacity(
                  pulses ? phase : DesignTokens.Today.glowLow),
                radius: pulses ? DesignTokens.Today.glowRadius * phase : 0)
          }
        }
        VStack(spacing: DesignTokens.Spacing.s4) {
          Text(evidence.count, format: .number)
            .font(DesignTokens.IdentityFigures.learningCount).monospacedDigit()
          Text("of 60").dielBodyStyle()
        }
      }
      .frame(
        width: diameter, height: diameter)
      Text("Learning your baseline").dielBodyStyle()
    }
    .frame(maxWidth: .infinity)
    .padding(DesignTokens.Spacing.cardPadding)
    .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Learning your baseline")
    .accessibilityValue("\(evidence.count) of 60 days with HRV and resting heart rate")
    .accessibilityIdentifier("readiness-learning-figure")
    .onScrollVisibilityChange(threshold: DesignTokens.Today.visibilityThreshold) { visible = $0 }
    .onAppear { visible = true }
    .onDisappear { visible = false }
    .task(id: LearningClockRequest(active: clockActive, adjustment: clockAdjustment)) {
      guard clockActive else { return }
      currentTime = Date()
      while !Task.isCancelled {
        guard let next = TodayClock.nextBoundary(after: currentTime, calendar: .current) else {
          return
        }
        do {
          try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow)))
        } catch { return }
        guard !Task.isCancelled else { return }
        currentTime = Date()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
    ) { _ in
      refreshClock()
    }
    .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
      refreshClock()
    }
  }

  private func refreshClock() {
    guard clockActive else { return }
    currentTime = Date()
    clockAdjustment += 1
  }
}

private struct LearningClockRequest: Equatable {
  let active: Bool
  let adjustment: Int
}

nonisolated private struct LearningTick: Shape {
  let index: Int
  let count: Int

  func path(in rect: CGRect) -> Path {
    let angle =
      DesignTokens.Today.ringStart * .pi / 180
      + Double(index) / Double(max(count, 1)) * DesignTokens.Today.fullTurn
    let radius = min(rect.width, rect.height) / 2 - DesignTokens.IdentityFigures.learningTickInset
    let inner = radius - DesignTokens.IdentityFigures.learningTickLength
    var path = Path()
    path.move(to: CGPoint(x: rect.midX + cos(angle) * inner, y: rect.midY + sin(angle) * inner))
    path.addLine(
      to: CGPoint(x: rect.midX + cos(angle) * radius, y: rect.midY + sin(angle) * radius))
    return path
  }
}

struct LastNightSummary: View {
  let highlights: TodayHighlights

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
      Text("Last night").font(.headline)
      Text(highlights.sleepDuration).font(.largeTitle.weight(.semibold)).monospacedDigit()
      SleepStageComposition(stages: highlights.stages)
      SleepWindowTimes(window: highlights.sleepWindow)
      SleepStageTotals(stages: highlights.stages)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("last-night-composition")
  }
}

struct SleepWindowTimes: View {
  let window: SleepWindow?

  var body: some View {
    if let window {
      HStack {
        Text(window.startText).accessibilityIdentifier("sleep-bedtime")
        Spacer(minLength: DesignTokens.Spacing.s8)
        Text(window.endText).accessibilityIdentifier("sleep-wake-time")
      }
      .dielBodyStyle().monospacedDigit()
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("Bedtime \(window.startText), wake time \(window.endText)")
      .accessibilityIdentifier("sleep-window-times")
    } else {
      Text("Sleep times unavailable").dielBodyStyle()
    }
  }
}
