import Foundation
import Observation
import ScoringKit

nonisolated final class TrendsPresentation: Sendable {
  let points: [TodayMetric: [DayChartPoint]]

  init(history: [ScoredDay], ending: ScoringDate, range: Int) {
    assert(!Thread.isMainThread)
    points = Dictionary(
      uniqueKeysWithValues: TodayMetric.allCases.map { metric in
        (
          metric,
          DayChartPoint.points(metric: metric, ending: ending, count: range, history: history)
        )
      })
  }
}

nonisolated struct TrendsPresentationRequest: Equatable, Sendable {
  let generation: UInt64
  let ending: ScoringDate?
  let range: Int
  var timeZone = TimeZone.current.identifier
}

@Observable
@MainActor
final class TrendsPresentationModel {
  private(set) var presentation: TrendsPresentation?
  @ObservationIgnored private var request: TrendsPresentationRequest?
  @ObservationIgnored private var job: Task<Void, Never>?

  func update(request: TrendsPresentationRequest, history: [ScoredDay]) async {
    if self.request == request {
      await job?.value
      return
    }
    job?.cancel()
    self.request = request
    guard let ending = request.ending else {
      presentation = nil
      job = nil
      return
    }
    // This shared job owns publication. Cancelling a view's waiter does not cancel a valid
    // build or leave the cached request without its completed presentation.
    let job = Task {
      let result = await Task.detached {
        TrendsPresentation(history: history, ending: ending, range: request.range)
      }.value
      guard !Task.isCancelled, self.request == request else { return }
      presentation = result
    }
    self.job = job
    await job.value
  }
}
