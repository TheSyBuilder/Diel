import SwiftUI

enum DesignTokens {
  enum DialScale {
    case score, load

    struct Stop {
      let location: Double
      let hex: UInt32
    }

    struct Components: Equatable {
      let red: Double
      let green: Double
      let blue: Double

      init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
      }

      init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
      }

      var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

      private var luminance: Double {
        func linear(_ value: Double) -> Double {
          value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
      }

      func contrast(on background: Self) -> Double {
        (max(luminance, background.luminance) + 0.05)
          / (min(luminance, background.luminance) + 0.05)
      }

      func blendedTowardWhite(by amount: Double) -> Self {
        Self(
          red: red + (1 - red) * amount, green: green + (1 - green) * amount,
          blue: blue + (1 - blue) * amount)
      }

      func darkened(by amount: Double) -> Self {
        let brightness = 1 - min(max(amount, 0), 1)
        return Self(red: red * brightness, green: green * brightness, blue: blue * brightness)
      }

      /// Retain passing tips exactly; otherwise find the smallest sRGB white blend.
      func foreground(on background: Self) -> Self {
        guard contrast(on: background) < DialForeground.minimumContrast else { return self }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<DialForeground.searchIterations {
          let middle = (lower + upper) / 2
          if blendedTowardWhite(by: middle).contrast(on: background)
            >= DialForeground.minimumContrast + DialForeground.renderingMargin
          {
            upper = middle
          } else {
            lower = middle
          }
        }
        return blendedTowardWhite(by: upper)
      }
    }

    var stops: [Stop] {
      switch self {
      case .score:
        [
          Stop(location: 0, hex: 0xEE3E55),
          Stop(location: 0.45, hex: 0xFF5A1F),
          Stop(location: 0.75, hex: 0xFF9A1F),
          Stop(location: 1, hex: 0xFFD23F),
        ]
      case .load:
        [Stop(location: 0, hex: 0xC2410C), Stop(location: 1, hex: 0xFF8A3D)]
      }
    }

    func components(at fraction: Double) -> Components {
      let fraction = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
      let stops = stops
      for pair in zip(stops, stops.dropFirst()) where fraction <= pair.1.location {
        let lower = Components(hex: pair.0.hex)
        let upper = Components(hex: pair.1.hex)
        let amount = (fraction - pair.0.location) / (pair.1.location - pair.0.location)
        return Components(
          red: lower.red + (upper.red - lower.red) * amount,
          green: lower.green + (upper.green - lower.green) * amount,
          blue: lower.blue + (upper.blue - lower.blue) * amount)
      }
      return Components(hex: stops[stops.count - 1].hex)
    }

    func color(at fraction: Double) -> Color {
      components(at: fraction).color
    }
  }

  struct DialFlow {
    static let startDarkening = 0.55

    let fraction: Double
    let start: DialScale.Components
    let tip: DialScale.Components

    init(scale: DialScale, progress: Double) {
      fraction = progress.isFinite ? min(max(progress, 0), 1) : 0
      tip = scale.components(at: fraction)
      start = tip.darkened(by: Self.startDarkening)
    }

    var gradient: Gradient { Gradient(colors: [start.color, tip.color]) }
  }

  enum DialForeground {
    static let minimumContrast = 4.5
    static let renderingMargin = 0.000001
    static let searchIterations = 64
  }

  enum Typography {
    static let screenTitle = Font.largeTitle.bold()
    static let sectionLabel = Font.subheadline.weight(.semibold)
    static let body = Font.subheadline
    static let caption = Font.subheadline
    static let sectionLabelTracking: CGFloat = 0.6

    fileprivate static let dialNumberSize: CGFloat = 44
    fileprivate static let heroNumberSize: CGFloat = 64
  }

  enum Spacing {
    static let s4: CGFloat = 4
    static let s8: CGFloat = 8
    static let s12: CGFloat = 12
    static let s16: CGFloat = 16
    static let s24: CGFloat = 24
    static let s32: CGFloat = 32
    static let s48: CGFloat = 48

    static let screenMargin: CGFloat = 20
    static let cardGap = s12
    static let cardPadding = s16
  }

  enum Today {
    static let heroDiameter: CGFloat = 200
    static let chartHeight: CGFloat = 144
    static let detailChartHeight: CGFloat = 200
    static let batteryWakeBarHeight: CGFloat = 64
    static let stageHeight: CGFloat = 10
    static let detailStageHeight: CGFloat = 32
    static let pointSize: CGFloat = 36
    static let cursorWidth: CGFloat = 1
    static let traceWidth: CGFloat = 2
    static let pressScale: CGFloat = 0.98
    static let pulseScale: CGFloat = 1.8
    static let scrollRise: CGFloat = 16
    static let scrollOpacity = 0.6
    static let bandOpacity = 0.65
    static let pointOpacity = 0.20
    static let batteryFillOpacity = 0.20
    static let batterySolidFillOpacity = 0.10
    static let dialDiameter: CGFloat = 112
    static let ringInset: CGFloat = 8
    static let ringStrokeFraction: CGFloat = 0.10
    static let selectedStroke: CGFloat = 1
    static let numberScale: CGFloat = 0.65
    static let cardNumber = Font.title2.weight(.semibold)
    /// A card headline written in words, such as a night Garmin has not received yet.
    static let cardHeadline = Font.title2.weight(.semibold)
    /// A released chart scrub keeps its rule and value this long, matching sleep selections.
    static let selectionHold = SleepComposition.historySelectionDuration
    static let sweepDuration = 0.8
    static let interactionDuration = 0.3
    static let breathCycle = 6.0
    static let timelineInterval = 1.0 / 30.0
    static let glowRadius: CGFloat = 10
    static let glowLow = 0.10
    static let glowTopExtension: CGFloat = 120
    static let glowRadiusFraction = 0.85
    static let glowShadeStop = 0.55
    static let glowTransitionDuration = 0.3
    nonisolated static let fullTurn = 2.0 * Double.pi
    static let staleInterval = 12.0 * 60.0 * 60.0
    nonisolated static let ringStart = -90.0
    static let visibilityThreshold = 0.1
  }

  enum IdentityFigures {
    static let learningDiameter: CGFloat = 168
    nonisolated static let learningTickLength: CGFloat = 8
    static let learningTickWidth: CGFloat = 2.5
    nonisolated static let learningTickInset: CGFloat = 8
    static let learningCount = Font.largeTitle.weight(.semibold)
    static let sleepArcHeight: CGFloat = 136
    static let sleepArcStroke: CGFloat = 2
    static let sleepArcDash: CGFloat = 1
    static let sleepArcGap: CGFloat = 7
    static let sleepEndpointSize: CGFloat = 6
    static let sleepArcInset: CGFloat = 12
  }

  enum SleepComposition {
    static let minimumSegmentWidth: CGFloat = 4
    static let historySelectionDuration = 3.0
    nonisolated static let minimumHistoryHeadroomMinutes = 5.0
    nonisolated static let nearNeedMinutes = 5.0
    static let shortHistoryHeight: CGFloat = 96
    nonisolated static let historyRangeHeadroom = 1.15
    static let historyBarWidthFraction = 0.64
  }

  enum Morning {
    static let minimumButtonHeight: CGFloat = 64
    static let ratingFont = Font.title.weight(.semibold)
  }

  enum Shape {
    static let cardRadius: CGFloat = 20
    static let cardStyle = RoundedCornerStyle.continuous
  }

  enum Appearance {
    static let iconSize = Spacing.s48
    static let iconRadius = Spacing.s12
    static let transitionDuration = 0.3
  }
}

extension View {
  func dielDialNumberStyle() -> some View {
    modifier(ScaledNumberStyle(size: DesignTokens.Typography.dialNumberSize))
  }

  func dielHeroNumberStyle() -> some View {
    modifier(ScaledNumberStyle(size: DesignTokens.Typography.heroNumberSize))
  }

  func dielScreenTitleStyle() -> some View {
    modifier(ThemedTextStyle(font: DesignTokens.Typography.screenTitle, primary: true))
  }

  /// Supply an uppercase localized literal so translators can choose appropriate casing.
  func dielSectionLabelStyle() -> some View {
    modifier(ThemedTextStyle(font: DesignTokens.Typography.sectionLabel))
      .tracking(DesignTokens.Typography.sectionLabelTracking)
  }

  func dielBodyStyle() -> some View {
    modifier(ThemedTextStyle(font: DesignTokens.Typography.body))
  }

  func dielCaptionStyle() -> some View {
    modifier(ThemedTextStyle(font: DesignTokens.Typography.caption))
  }
}

private struct ThemedTextStyle: ViewModifier {
  @Environment(\.dielTheme) private var theme
  let font: Font
  var primary = false

  func body(content: Content) -> some View {
    content
      .font(font)
      .foregroundStyle(primary ? theme.colors.textPrimary : theme.colors.textSecondary)
  }
}

private struct ScaledNumberStyle: ViewModifier {
  @ScaledMetric private var size: CGFloat

  init(size: CGFloat) {
    _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle)
  }

  func body(content: Content) -> some View {
    content
      .font(.system(size: size, weight: .semibold))
      .monospacedDigit()
  }
}
