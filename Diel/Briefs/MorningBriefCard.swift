import SwiftUI

struct MorningBriefCard: View {
  @Environment(\.dielTheme) private var theme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let brief: Brief
  let open: () -> Void
  @State private var appeared = false

  var body: some View {
    Button(action: open) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s8) {
        Text(brief.headline).font(.headline).foregroundStyle(theme.colors.textPrimary)
        Text(brief.body).dielBodyStyle().fixedSize(horizontal: false, vertical: true)
      }
      .opacity(reduceMotion || appeared ? 1 : 0)
      .animation(
        reduceMotion ? nil : .easeInOut(duration: DesignTokens.Appearance.transitionDuration),
        value: appeared
      )
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DesignTokens.Spacing.cardPadding)
      .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .onAppear { appeared = true }
    .contentTransition(reduceMotion ? .identity : .opacity)
    .animation(
      reduceMotion ? nil : .easeInOut(duration: DesignTokens.Appearance.transitionDuration),
      value: brief
    )
    .accessibilityElement(children: .combine)
    .accessibilityHint("Opens Readiness details")
    .accessibilityIdentifier("today-morning-brief")
  }
}

/// Input changes deliver the latest answer to pending retries. The score-only cache context
/// still prevents an answer edit from independently triggering model generation.
struct MorningBriefRequest {
  struct ID: Equatable {
    let context: BriefCacheContext?
    let input: BriefInput?
    let settled: Bool
  }
  let context: BriefCacheContext?
  let input: BriefInput?
  let settled: Bool
  var id: ID { ID(context: context, input: input, settled: settled) }
}
