import SwiftUI

struct TodayEvidenceCard: View {
  @Environment(\.dielTheme) private var theme
  let title: String
  let subtitle: String
  let rows: [TodayEvidenceRow]
  var selected = false
  var colour: Color?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.s16) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
        Text(title).dielSectionLabelStyle()
        Text(subtitle).dielCaptionStyle()
      }
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.s4) {
          HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.s8) {
            Text(row.label).dielBodyStyle()
            Spacer(minLength: DesignTokens.Spacing.s4)
            Text(row.value).font(DesignTokens.Typography.body.weight(.semibold))
              .foregroundStyle(theme.colors.textPrimary).monospacedDigit()
              .multilineTextAlignment(.trailing)
          }
          Text(row.detail).dielCaptionStyle().fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("today-evidence-\(row.id)")
      }
    }
    .accessibilityElement(children: .contain)
    .padding(DesignTokens.Spacing.cardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
    .overlay {
      RoundedRectangle(cornerRadius: DesignTokens.Shape.cardRadius)
        .stroke(
          selected ? colour ?? theme.colors.hairline : theme.colors.hairline,
          lineWidth: DesignTokens.Today.selectedStroke)
    }
  }
}
