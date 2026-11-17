#if DEBUG
  import SwiftUI

  struct SampleDataBanner: View {
    @Environment(\.dielTheme) private var theme
    let dayCount: Int

    var body: some View {
      Text("Sample data")
        .font(DesignTokens.Typography.body)
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.horizontal, DesignTokens.Spacing.s16)
        .padding(.vertical, DesignTokens.Spacing.s4)
        .background(theme.colors.surface, in: .capsule)
        .accessibilityIdentifier("sample-data")
    }
  }
#endif
