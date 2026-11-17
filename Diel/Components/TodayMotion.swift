import ScoringKit
import SwiftUI

/// Only the animated surface receives timeline ticks. Pauses retain their phase.
struct TodayMotion<Content: View>: View {
  let running: Bool
  let cycle: Double
  @ViewBuilder let content: (Double) -> Content
  @State private var elapsed = 0.0
  @State private var startedAt: Date?

  var body: some View {
    TimelineView(.animation(minimumInterval: DesignTokens.Today.timelineInterval, paused: !running))
    { timeline in
      let duration = elapsed + (startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0)
      content((sin(duration / cycle * DesignTokens.Today.fullTurn) + 1) / 2)
    }
    .onChange(of: running, initial: true) { _, active in
      if active {
        startedAt = Date()
      } else if let startedAt {
        elapsed += Date().timeIntervalSince(startedAt)
        self.startedAt = nil
      }
    }
  }
}

/// A static theme light whose strength follows today's available Readiness.
struct TodayGlow: View {
  @Environment(\.dielTheme) private var theme
  let readiness: Double?
  let band: ScoreBand?
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let glow = theme.todayGlow(
      readiness: readiness, band: band, reduceTransparency: reduceTransparency)
    GeometryReader { geometry in
      ZStack {
        if let glow {
          RadialGradient(
            stops: [
              .init(color: glow.colors.tintColor, location: 0),
              .init(color: glow.colors.shadeColor, location: DesignTokens.Today.glowShadeStop),
              .init(color: theme.colors.canvas.opacity(0), location: 1),
            ],
            center: .top, startRadius: 0,
            endRadius: max(geometry.size.width, geometry.size.height)
              * DesignTokens.Today.glowRadiusFraction
          )
          .opacity(glow.strength)
          .id(glow.colors)
          .transition(.opacity)
        }
      }
      .animation(
        reduceMotion || reduceTransparency
          ? nil : .easeInOut(duration: DesignTokens.Today.glowTransitionDuration),
        value: glow?.colors
      )
      .transaction { transaction in
        if reduceMotion || reduceTransparency {
          transaction.animation = nil
          transaction.disablesAnimations = true
        }
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

extension TodayDial {
  var ringScale: DesignTokens.DialScale { metric == .load ? .load : .score }
}

extension DialColour {
  var scoreBand: ScoreBand? {
    guard case .band(let band) = self else { return nil }
    return band
  }
}

extension DielTheme {
  func dialForeground(_ dial: TodayDial) -> Color {
    guard self == .ember, dial.metric == .load, let progress = dial.progress else {
      return dialColor(dial)
    }
    return loadForegroundComponents(at: progress).color
  }

  func dialColor(_ dial: TodayDial) -> Color {
    if dial.metric == .load {
      return usesFlow
        ? dial.progress.map { dial.ringScale.color(at: $0) } ?? colors.load
        : colors.load
    }
    return scoreColor(
      value: dial.value, band: dial.colour.scoreBand,
      kind: dial.metric == .sleep ? .sleep : .readiness)
  }
}
