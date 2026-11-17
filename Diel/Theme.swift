import ScoringKit
import SwiftUI

enum DielTheme: String, CaseIterable, Identifiable, Sendable {
  case ember, lunar, classic

  var id: String { rawValue }
  var name: LocalizedStringResource {
    switch self {
    case .ember: "Ember"
    case .lunar: "Lunar"
    case .classic: "Classic"
    }
  }

  var usesFlow: Bool { self == .ember }
  var alternateIconName: String? {
    switch self {
    case .ember: nil
    case .lunar: "DielLunar"
    case .classic: "DielClassic"
    }
  }
  var iconAssetName: String { alternateIconName ?? "Diel" }
  var previewAssetName: String {
    switch self {
    case .ember: "ThemePreviewEmber"
    case .lunar: "ThemePreviewLunar"
    case .classic: "ThemePreviewClassic"
    }
  }

  var palette: ThemePalette {
    switch self {
    case .ember:
      ThemePalette(
        canvas: 0x0A0A0A, surface: 0x161514, surfaceRaised: 0x24211F,
        hairline: 0x2E2A27, textPrimary: 0xF7F5F3, textSecondary: 0xA7A19C,
        textTertiary: 0x918B86, error: 0xEE3E55, load: 0xFF5A1F,
        good: 0xFFD23F, caution: 0xFF9A1F, low: 0xEE3E55,
        deep: 0x9A3412, light: 0xE76F20, rem: 0xFFB45C, awake: 0xFFE3BF)
    case .lunar:
      ThemePalette(
        canvas: 0x050506, surface: 0x111214, surfaceRaised: 0x1C1D21,
        hairline: 0x2C2F35, textPrimary: 0xF2F4F7, textSecondary: 0x9A9FA8,
        textTertiary: 0x9A9FA8, error: 0xFF5F57, load: 0xA9B8D6,
        good: 0xF2F4F7, caution: 0xC9A86A, low: 0xFF5F57,
        deep: 0x48566F, light: 0x8499B8, rem: 0xBCCBE0, awake: 0xF2F4F7)
    case .classic:
      ThemePalette(
        canvas: 0x0A0A0A, surface: 0x161514, surfaceRaised: 0x24211F,
        hairline: 0x2E2A27, textPrimary: 0xF7F5F3, textSecondary: 0xA7A19C,
        textTertiary: 0x918B86, error: 0xEE3E55, load: 0xFF5A1F,
        good: 0x1EE6B4, caution: 0xFFC233, low: 0xEE3E55,
        deep: 0x625B57, light: 0xA0968E, rem: 0xD0C6BC, awake: 0xF7F5F3)
    }
  }

  var colors: ThemeColors { ThemeColors(palette: palette) }

  func loadForegroundComponents(at fraction: Double) -> DesignTokens.DialScale.Components {
    let tip = DesignTokens.DialScale.load.components(at: fraction)
    return tip.foreground(on: .init(hex: palette.canvas))
  }

  func todayGlow(
    readiness: Double?, band: ScoreBand? = nil, reduceTransparency: Bool = false
  ) -> ResolvedThemeGlow? {
    guard !reduceTransparency, let readiness, readiness.isFinite,
      let band = scoreBand(value: readiness, band: band)
    else { return nil }
    let tokens = glowTokens(band: band)
    let fraction = min(max(readiness / 100, 0), 1)
    return ResolvedThemeGlow(
      colors: tokens.colors,
      strength: tokens.minimum + fraction * (tokens.maximum - tokens.minimum))
  }

  func glowTokens(band: ScoreBand) -> ThemeGlowTokens {
    switch self {
    case .ember:
      ThemeGlowTokens(tint: 0xFF5A1F, shade: 0x2C1508, minimum: 0.08, maximum: 0.24)
    case .lunar:
      ThemeGlowTokens(tint: 0xD6DEEB, shade: 0x1C1E24, minimum: 0.10, maximum: 0.18)
    case .classic:
      switch band {
      case .upper:
        ThemeGlowTokens(tint: palette.good, shade: 0x062E24, minimum: 0.12, maximum: 0.18)
      case .middle:
        ThemeGlowTokens(tint: palette.caution, shade: 0x33270A, minimum: 0.12, maximum: 0.18)
      case .lower:
        ThemeGlowTokens(tint: palette.low, shade: 0x300C11, minimum: 0.12, maximum: 0.18)
      }
    }
  }

  /// An engine-supplied band wins; fallback cutoffs come from the active scoring configurations.
  func scoreBand(value: Double?, band: ScoreBand? = nil, kind: ScoreKind = .readiness)
    -> ScoreBand?
  {
    guard kind != .load, let value, value.isFinite else { return nil }
    if let band { return band }
    let bands = kind == .sleep ? ScoringConfig.v1.sleepBands : ReadinessV2Config.v2_2.bands
    if value >= bands.upperStartsAt { return .upper }
    return value >= bands.middleStartsAt ? .middle : .lower
  }

  func scoreColor(value: Double?, band: ScoreBand? = nil, kind: ScoreKind = .readiness) -> Color {
    if kind == .load { return colors.load }
    guard let resolved = scoreBand(value: value, band: band, kind: kind), let value else {
      return colors.textTertiary
    }
    if usesFlow { return DesignTokens.DialScale.score.color(at: value / 100) }
    switch resolved {
    case .upper: return colors.good
    case .middle: return colors.caution
    case .lower: return colors.low
    }
  }
}

struct ThemePalette: Equatable, Sendable {
  let canvas: UInt32
  let surface: UInt32
  let surfaceRaised: UInt32
  let hairline: UInt32
  let textPrimary: UInt32
  let textSecondary: UInt32
  let textTertiary: UInt32
  let error: UInt32
  let load: UInt32
  let good: UInt32
  let caution: UInt32
  let low: UInt32
  let deep: UInt32
  let light: UInt32
  let rem: UInt32
  let awake: UInt32
  var brand: UInt32 { load }
}

struct ThemeGlowColors: Hashable, Sendable {
  let tint: UInt32
  let shade: UInt32
  var tintColor: Color { DesignTokens.DialScale.Components(hex: tint).color }
  var shadeColor: Color { DesignTokens.DialScale.Components(hex: shade).color }
}

struct ThemeGlowTokens: Equatable, Sendable {
  let colors: ThemeGlowColors
  let minimum: Double
  let maximum: Double

  init(tint: UInt32, shade: UInt32, minimum: Double, maximum: Double) {
    colors = ThemeGlowColors(tint: tint, shade: shade)
    self.minimum = minimum
    self.maximum = maximum
  }
}

struct ResolvedThemeGlow: Equatable, Sendable {
  let colors: ThemeGlowColors
  let strength: Double
}

struct ThemeColors {
  let palette: ThemePalette
  var canvas: Color { color(palette.canvas) }
  var surface: Color { color(palette.surface) }
  var surfaceRaised: Color { color(palette.surfaceRaised) }
  var hairline: Color { color(palette.hairline) }
  var textPrimary: Color { color(palette.textPrimary) }
  var textSecondary: Color { color(palette.textSecondary) }
  var textTertiary: Color { color(palette.textTertiary) }
  var error: Color { color(palette.error) }
  var load: Color { color(palette.load) }
  var brand: Color { color(palette.brand) }
  var good: Color { color(palette.good) }
  var caution: Color { color(palette.caution) }
  var low: Color { color(palette.low) }

  func sleepStage(_ stage: SleepStage) -> Color {
    switch stage {
    case .deep: color(palette.deep)
    case .light: color(palette.light)
    case .rem: color(palette.rem)
    case .awake: color(palette.awake)
    }
  }

  private func color(_ hex: UInt32) -> Color {
    Color(
      .sRGB, red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

extension EnvironmentValues {
  @Entry var dielTheme: DielTheme = .ember
}
