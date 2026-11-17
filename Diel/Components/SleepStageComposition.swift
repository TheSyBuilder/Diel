import SwiftUI
import UIKit

/// Display widths may protect short stages, while every readout retains Garmin's real total.
nonisolated struct SleepCompositionLayout {
  nonisolated struct Segment: Identifiable, Equatable {
    let total: SleepStageTotal
    let lower: Double
    let upper: Double
    var id: SleepStage { total.stage }
    var width: Double { upper - lower }
  }

  let totals: [SleepStageTotal]
  let segments: [Segment]
  let width: Double

  init?(stages: [SleepStageTotal], width: Double, minimumWidth: Double) {
    guard width.isFinite, width > 0, minimumWidth.isFinite, minimumWidth >= 0,
      stages.count == SleepStage.compositionOrder.count,
      Set(stages.map(\.stage)).count == SleepStage.compositionOrder.count
    else { return nil }
    totals = SleepStage.compositionOrder.compactMap { stage in
      stages.first { $0.stage == stage }
    }
    self.width = width
    let positive = totals.filter { $0.seconds > 0 }
    let minimum = min(minimumWidth, width / Double(max(positive.count, 1)))
    var lengths: [SleepStage: Double] = [:]
    var remaining = positive
    var available = width
    // Fix undersized stages first, then redistribute the remaining width proportionally.
    while !remaining.isEmpty {
      let seconds = remaining.reduce(0.0) { $0 + Double($1.seconds) }
      let short = remaining.filter { available * Double($0.seconds) / seconds < minimum }
      if short.isEmpty {
        for total in remaining {
          lengths[total.stage] = available * Double(total.seconds) / seconds
        }
        break
      }
      for total in short { lengths[total.stage] = minimum }
      available -= minimum * Double(short.count)
      let fixed = Set(short.map(\.stage))
      remaining.removeAll { fixed.contains($0.stage) }
    }
    var lower = 0.0
    segments = positive.map { total in
      let upper = total.stage == positive.last?.stage ? width : lower + (lengths[total.stage] ?? 0)
      defer { lower = upper }
      return Segment(total: total, lower: lower, upper: upper)
    }
  }

  func selected(at fraction: Double) -> SleepStageTotal? {
    guard fraction.isFinite, !segments.isEmpty else { return nil }
    let position = min(max(fraction, 0), 1) * width
    return segments.first { position >= $0.lower && position < $0.upper }?.total
      ?? segments.last?.total
  }
}

struct SleepStageComposition: View {
  let stages: [SleepStageTotal]
  var compact = false
  @State private var selection: SleepStage?
  @State private var feedback = 0
  @State private var dismissal: Task<Void, Never>?
  @State private var touching = false

  private var selected: SleepStageTotal? { stages.first { $0.stage == selection } }
  private var orderedTotals: [SleepStageTotal] {
    SleepStage.compositionOrder.compactMap { stage in stages.first { $0.stage == stage } }
  }
  private var accessibilitySummary: String {
    if let selected {
      return "\(selected.stage.title), \(selected.duration)"
    }
    let summaries: [String] = orderedTotals.map { total in
      "\(total.stage.title), \(total.duration)"
    }
    return summaries.joined(separator: "; ")
  }
  private var complete: Bool {
    stages.count == SleepStage.compositionOrder.count
      && Set(stages.map(\.stage)).count == SleepStage.compositionOrder.count
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
      if complete {
        GeometryReader { geometry in
          if let layout = SleepCompositionLayout(
            stages: stages, width: geometry.size.width,
            minimumWidth: DesignTokens.SleepComposition.minimumSegmentWidth)
          {
            SleepCompositionBar(layout: layout, selection: selection)
              .frame(
                height: compact
                  ? DesignTokens.Today.stageHeight : DesignTokens.Today.detailStageHeight
              )
              .frame(maxHeight: .infinity)
              .contentShape(.rect)
              .gesture(
                HorizontalScrubGesture { location in
                  select(layout.selected(at: location.x / geometry.size.width)?.stage)
                }
              )
              .gesture(SleepCompositionTouchGesture(changed: updateTouch))
              .onTapGesture(coordinateSpace: .local) { location in
                select(layout.selected(at: location.x / geometry.size.width)?.stage)
              }
          }
        }
        .frame(height: DesignTokens.Spacing.s48)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sleep stage totals")
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint("Adjust to hear each stage's total duration")
        .accessibilityAdjustableAction { direction in
          let index = orderedTotals.firstIndex { $0.stage == selection }
          let next: Int
          if direction == .increment {
            next = min((index ?? -1) + 1, orderedTotals.count - 1)
          } else {
            next = max((index ?? orderedTotals.count) - 1, 0)
          }
          if orderedTotals.indices.contains(next) { select(orderedTotals[next].stage) }
        }
        .accessibilityIdentifier("sleep-stage-scrubber")
        if let selected {
          HStack {
            Text(selected.stage.title)
            Spacer()
            Text(selected.duration).monospacedDigit()
          }
          .dielBodyStyle()
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(selected.stage.title), \(selected.duration)")
          .accessibilityIdentifier("sleep-stage-selection")
        }
      } else {
        Text("Sleep stages unavailable").dielBodyStyle()
          .accessibilityIdentifier("sleep-stage-unavailable")
      }
    }
    .sensoryFeedback(.selection, trigger: feedback)
    .onChange(of: stages) { _, _ in resetSelection() }
    .onDisappear { resetSelection() }
  }

  private func updateTouch(_ active: Bool) {
    guard touching != active else { return }
    touching = active
    scheduleDismissal()
  }

  private func select(_ stage: SleepStage?) {
    guard let stage else { return }
    if stage != selection {
      selection = stage
      feedback += 1
    }
    scheduleDismissal()
  }

  private func scheduleDismissal() {
    dismissal?.cancel()
    guard selection != nil, !touching else { return }
    dismissal = Task {
      do {
        try await Task.sleep(for: .seconds(DesignTokens.SleepComposition.historySelectionDuration))
        guard !Task.isCancelled else { return }
        selection = nil
      } catch {}
    }
  }

  private func resetSelection() {
    selection = nil
    touching = false
    dismissal?.cancel()
    dismissal = nil
  }
}

/// Observes contact without taking scrolling or navigation away from their own recognizers.
private struct SleepCompositionTouchGesture: UIGestureRecognizerRepresentable {
  let changed: (Bool) -> Void

  func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

  func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
    let recognizer = UILongPressGestureRecognizer()
    recognizer.minimumPressDuration = 0
    recognizer.allowableMovement = .greatestFiniteMagnitude
    recognizer.cancelsTouchesInView = false
    recognizer.delegate = context.coordinator
    return recognizer
  }

  func handleUIGestureRecognizerAction(
    _ recognizer: UILongPressGestureRecognizer, context: Context
  ) {
    changed(recognizer.state == .began || recognizer.state == .changed)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    func gestureRecognizer(
      _ gestureRecognizer: UIGestureRecognizer,
      shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }
  }
}

private struct SleepCompositionBar: View {
  @Environment(\.dielTheme) private var theme
  let layout: SleepCompositionLayout
  let selection: SleepStage?

  var body: some View {
    HStack(spacing: 0) {
      ForEach(layout.segments) { segment in
        Rectangle().fill(theme.colors.sleepStage(segment.total.stage))
          .frame(width: segment.width)
          .overlay {
            if selection == segment.total.stage {
              Rectangle().strokeBorder(
                theme.colors.textPrimary, lineWidth: DesignTokens.Today.traceWidth)
            }
          }
      }
    }
    .frame(width: layout.width)
    .background(theme.colors.surfaceRaised)
    .clipShape(.rect(cornerRadius: DesignTokens.Spacing.s4))
    .accessibilityHidden(true)
  }
}
