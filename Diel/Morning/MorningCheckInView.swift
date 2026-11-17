import SwiftUI

struct MorningCheckInView: View {
  @Environment(\.dielTheme) private var theme
  let coordinator: MorningCheckInCoordinator
  @AccessibilityFocusState private var questionFocused: Bool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s32) {
        Text("How do you feel?")
          .dielScreenTitleStyle()
          .accessibilityAddTraits(.isHeader)
          .accessibilityFocused($questionFocused)
        MorningRatingChoices(coordinator: coordinator)
        if let error = coordinator.errorMessage {
          Text(error).dielBodyStyle()
            .foregroundStyle(theme.colors.error)
            .accessibilityIdentifier("check-in-error")
          if !coordinator.hasLoaded {
            Button("Retry") { Task { await coordinator.evaluate() } }
              .buttonStyle(.borderedProminent)
              .tint(theme.colors.brand)
              .disabled(coordinator.isChecking)
          }
        }
        Button("Skip") { Task { await coordinator.complete(rating: nil) } }
          .font(DesignTokens.Typography.body)
          .foregroundStyle(theme.colors.textSecondary)
          .frame(minHeight: DesignTokens.Morning.minimumButtonHeight)
          .disabled(!coordinator.hasLoaded || coordinator.isChecking || coordinator.isSaving)
          .accessibilityIdentifier("check-in-skip")
      }
      .padding(.horizontal, DesignTokens.Spacing.screenMargin)
      .padding(.vertical, DesignTokens.Spacing.s48)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(theme.colors.canvas)
    .interactiveDismissDisabled()
    .accessibilityIdentifier("morning-check-in")
    .task { questionFocused = true }
  }
}

private struct MorningRatingChoices: View {
  @Environment(\.dynamicTypeSize) private var typeSize
  let coordinator: MorningCheckInCoordinator
  private let ratings = [1, 2, 3, 4, 5]

  var body: some View {
    VStack(spacing: DesignTokens.Spacing.s12) {
      if typeSize.isAccessibilitySize { Text("Drained").dielBodyStyle() }
      let layout =
        typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(spacing: DesignTokens.Spacing.s12))
        : AnyLayout(HStackLayout(spacing: DesignTokens.Spacing.s8))
      layout {
        ForEach(ratings, id: \.self) { rating in
          MorningRatingButton(rating: rating, selected: coordinator.answer?.rating == rating) {
            Task { await coordinator.complete(rating: rating) }
          }
        }
      }
      if typeSize.isAccessibilitySize {
        Text("Great").dielBodyStyle()
      } else {
        HStack {
          Text("Drained")
          Spacer()
          Text("Great")
        }.dielBodyStyle()
      }
    }
    .disabled(!coordinator.hasLoaded || coordinator.isChecking || coordinator.isSaving)
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Rate how you feel, 1 drained to 5 great")
  }
}

private struct MorningRatingButton: View {
  @Environment(\.dielTheme) private var theme
  let rating: Int
  let selected: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(rating, format: .number)
        .font(DesignTokens.Morning.ratingFont)
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: DesignTokens.Morning.minimumButtonHeight)
        .foregroundStyle(theme.colors.textPrimary)
        .background(
          theme.colors.surfaceRaised,
          in: .rect(cornerRadius: DesignTokens.Shape.cardRadius)
        )
        .overlay {
          if selected {
            RoundedRectangle(cornerRadius: DesignTokens.Shape.cardRadius)
              .strokeBorder(theme.colors.brand, lineWidth: DesignTokens.Today.traceWidth)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("check-in-rating-\(rating)")
  }
}

struct MorningCheckInChip: View {
  @Environment(\.dielTheme) private var theme
  let coordinator: MorningCheckInCoordinator

  var body: some View {
    if coordinator.hasLoaded {
      Button {
        coordinator.editToday()
      } label: {
        if let rating = coordinator.answer?.rating {
          Text("Feeling \(rating)")
        } else {
          Text("Check in")
        }
      }
      .font(DesignTokens.Typography.body)
      .buttonStyle(.bordered)
      .tint(theme.colors.brand)
      .accessibilityIdentifier("today-check-in")
    }
  }
}
