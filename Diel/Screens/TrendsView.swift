import ScoringKit
import SwiftUI

struct TrendsView: View {
  @Environment(\.dielTheme) private var theme
  @Environment(\.timeZone) private var timeZone
  let history: [ScoredDay]
  let ending: ScoringDate?
  let generation: UInt64
  @State private var range = 7
  @State private var model = TrendsPresentationModel()

  private var request: TrendsPresentationRequest {
    TrendsPresentationRequest(
      generation: generation, ending: ending, range: range, timeZone: timeZone.identifier)
  }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.s24) {
        Picker("Days", selection: $range) {
          Text("7 days").tag(7)
          Text("30 days").tag(30)
          Text("90 days").tag(90)
        }.pickerStyle(.segmented).accessibilityIdentifier("trends-range")
        if ending != nil {
          ForEach(TodayMetric.allCases) { metric in
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.s12) {
              Text(metric == .sleep ? "Garmin Sleep Score" : metric.title).font(.headline)
              MetricHistoryChart(
                metric: metric,
                points: model.presentation?.points[metric] ?? []
              )
              .id("\(metric.rawValue)-\(range)")
            }.accessibilityElement(children: .contain)
              .accessibilityIdentifier("trends-card-\(metric.rawValue)")
              .padding(DesignTokens.Spacing.cardPadding)
              .background(
                theme.colors.surface, in: .rect(cornerRadius: DesignTokens.Shape.cardRadius))
          }
        } else {
          Text("Your trends will appear after your first sync.").dielBodyStyle()
        }
      }.padding(DesignTokens.Spacing.screenMargin)
    }
    .dielTabScrollClearance()
    .background(theme.colors.canvas)
    .navigationTitle("Trends")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar { SampleDataToolbar() }
    .task(id: request) { await model.update(request: request, history: history) }
  }
}

struct TrendsTabView: View {
  let dependencies: AppDependencies
  var body: some View {
    NavigationStack {
      TrendsView(
        history: dependencies.scoring?.history ?? [],
        ending: dependencies.scoring?.days.last?.input.date,
        generation: dependencies.scoring?.publicationGeneration ?? 0)
    }
  }
}
