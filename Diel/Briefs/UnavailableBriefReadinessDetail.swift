import SwiftUI

/// A missing current day never borrows a historical score just to supply a navigation destination.
struct UnavailableBriefReadinessDetail: View {
  @Environment(\.dielTheme) private var theme
  @State private var showingCalculation = false

  private static let missingRows: [TodayEvidenceRow] = [
    .init(
      id: "latest-hrv", label: "Last night's HRV", value: "Unavailable",
      detail: "Your normal is unavailable"),
    .init(
      id: "hrv-trend", label: "HRV trend", value: "Unavailable",
      detail: "Your normal is unavailable"),
    .init(
      id: "daily-rhr", label: "Daily resting heart rate", value: "Unavailable",
      detail: "Your normal is unavailable"),
    .init(
      id: "rhr-trend", label: "Resting heart rate trend", value: "Unavailable",
      detail: "Your normal is unavailable"),
    .init(id: "last-night", label: "Last night", value: "Unavailable", detail: ""),
    .init(id: "sleep-need", label: "Your sleep need", value: "Unavailable", detail: ""),
    .init(id: "three-night", label: "Recent sleep", value: "Unavailable", detail: ""),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
        DetailHero(dial: .unavailable(.readiness))
        Text("Diel estimate").dielBodyStyle()
        DetailMeasurementRows(rows: Self.missingRows, heroReason: "No reading")
      }
      .padding(DesignTokens.Spacing.screenMargin)
    }
    .dielTabScrollClearance()
    .background(theme.colors.canvas)
    .navigationTitle("Readiness")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      SampleDataToolbar()
      ToolbarItem(placement: .topBarTrailing) {
        Button("How this is calculated", systemImage: "info.circle") { showingCalculation = true }
          .labelStyle(.iconOnly).accessibilityIdentifier("calculation-info")
      }
    }
    .sheet(isPresented: $showingCalculation) { CalculationSheet(topic: "Readiness") }
    .accessibilityIdentifier("detail-readiness")
  }
}
