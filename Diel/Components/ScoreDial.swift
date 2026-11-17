import SwiftUI

/// The ring drawing shared by Today controls and detail heroes.
@Animatable
struct DialRing: View {
  @AnimatableIgnored @Environment(\.dielTheme) private var theme
  var progress: Double
  let scale: DesignTokens.DialScale
  let tint: Color

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width * DesignTokens.Today.ringStrokeFraction
      let flow = DesignTokens.DialFlow(scale: scale, progress: progress)
      let fraction = flow.fraction
      let radius = (geometry.size.width - width) / 2
      let angle = fraction * DesignTokens.Today.fullTurn
      ZStack {
        ZStack {
          Circle().stroke(theme.colors.surfaceRaised, lineWidth: width)
          if fraction > 0 {
            Circle().trim(from: 0, to: fraction)
              .stroke(
                theme.usesFlow
                  ? AnyShapeStyle(
                    AngularGradient(
                      gradient: flow.gradient, center: .center,
                      startAngle: .zero, endAngle: .radians(angle)))
                  : AnyShapeStyle(tint),
                style: StrokeStyle(
                  lineWidth: width, lineCap: theme.usesFlow ? .butt : .round)
              )
              .rotationEffect(.degrees(DesignTokens.Today.ringStart))
          }
        }
        .padding(width / 2)
        if fraction > 0 {
          Circle().fill(theme.usesFlow ? flow.start.color : tint)
            .frame(width: width, height: width)
            .offset(y: -radius)
          Circle().fill(theme.usesFlow ? flow.tip.color : tint)
            .frame(width: width, height: width)
            .offset(x: radius * sin(angle), y: -radius * cos(angle))
        }
      }
    }
    .accessibilityHidden(true)
  }
}

struct ScoreDial: View {
  @Environment(\.dielTheme) private var theme
  let dial: TodayDial
  let active: Bool
  let syncing: Bool
  let selected: Bool
  let select: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var revealed = false

  private var label: LocalizedStringKey {
    switch dial.metric {
    case .readiness: "READINESS"
    case .load: "LOAD"
    case .sleep: "SLEEP"
    }
  }

  private var symbol: DielSymbol {
    switch dial.metric {
    case .readiness: .readiness
    case .load: .load
    case .sleep: .sleep
    }
  }

  private var progress: Double {
    guard revealed, !syncing || reduceMotion else { return 0 }
    return dial.progress ?? 0
  }

  var body: some View {
    Button(action: select) {
      VStack(spacing: DesignTokens.Spacing.s8) {
        face
        HStack(spacing: DesignTokens.Spacing.s4) {
          DielSymbolView(symbol, animateOnAppear: true)
          Text(label)
        }
        .font(DesignTokens.Typography.sectionLabel)
        .foregroundStyle(theme.dialForeground(dial))
        .minimumScaleFactor(DesignTokens.Today.numberScale)
        .lineLimit(1)
        Text(dial.reason).font(DesignTokens.Typography.body)
          .foregroundStyle(theme.colors.textSecondary)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .top)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(dial.accessibilityLabel)
    .accessibilityHint("Opens details")
    .accessibilityIdentifier("today-dial-\(dial.metric.rawValue)")
    .onAppear {
      revealed = true
    }
  }

  private var face: some View {
    ZStack {
      DialRing(progress: progress, scale: dial.ringScale, tint: theme.dialColor(dial))
        .padding(DesignTokens.Today.ringInset)
        .animation(
          reduceMotion ? nil : .smooth(duration: DesignTokens.Today.sweepDuration), value: progress)
      Text(dial.number)
        .dielDialNumberStyle()
        .foregroundStyle(theme.colors.textPrimary)
        .minimumScaleFactor(DesignTokens.Today.numberScale)
        .lineLimit(1)
        .padding(DesignTokens.Spacing.s16)
        .contentTransition(reduceMotion ? .identity : .numericText(value: dial.value ?? 0))
        .animation(
          reduceMotion ? nil : .smooth(duration: DesignTokens.Today.sweepDuration),
          value: dial.value)
    }
    .frame(width: DesignTokens.Today.dialDiameter, height: DesignTokens.Today.dialDiameter)
  }
}
