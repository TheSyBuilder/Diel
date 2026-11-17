import SwiftUI

/// Diel's text-aligned, weight-aware custom SF Symbols.
enum DielSymbol: String, CaseIterable {
  case readiness, load, sleep, hrv, stages, battery, breathing

  var assetName: String { "diel.\(rawValue)" }
}

/// Decorative by default; the enclosing metric or control supplies its spoken label.
struct DielSymbolView: View {
  let symbol: DielSymbol
  var animateOnAppear = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var appeared = false
  @State private var appearance = 0

  init(_ symbol: DielSymbol, animateOnAppear: Bool = false) {
    self.symbol = symbol
    self.animateOnAppear = animateOnAppear
  }

  var body: some View {
    animatedImage
      .symbolEffectsRemoved(reduceMotion || !animateOnAppear || scenePhase != .active)
      .accessibilityHidden(true)
      .onAppear {
        withAnimation(reduceMotion ? nil : .smooth(duration: DesignTokens.Today.sweepDuration)) {
          appeared = true
          if animateOnAppear && !reduceMotion && scenePhase == .active {
            appearance += 1
          }
        }
      }
      .onDisappear { appeared = false }
  }

  @ViewBuilder private var animatedImage: some View {
    switch symbol {
    case .readiness:
      // The hidden copy reserves text alignment while the visible symbol draws in.
      image.hidden().overlay {
        if appeared || !animateOnAppear || reduceMotion {
          image.transition(.symbolEffect(.drawOn))
        }
      }
    case .load:
      image.symbolEffect(.variableColor.iterative, options: .nonRepeating, value: appearance)
    case .sleep:
      image.symbolEffect(.breathe.wholeSymbol, options: .nonRepeating, value: appearance)
    default:
      image
    }
  }

  private var image: Image { Image(symbol.assetName).symbolRenderingMode(.monochrome) }

}
