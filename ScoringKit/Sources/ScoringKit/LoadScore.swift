import Foundation

public enum LoadScore {
  public static func calculate(
    day: ScoringDayInput, history: [ScoringDayInput], config: ScoringConfig = .v1
  ) -> LoadResult {
    let start = day.date.adding(days: -config.loadReferenceWindowDays)
    let groups = Dictionary(
      grouping: history.filter { candidate in
        start.map { candidate.date >= $0 && candidate.date < day.date } ?? false
      }, by: \.date)
    let duplicates = groups.filter { $0.value.count > 1 }.keys.sorted()
    let observations = groups.compactMap { date, days -> BaselineObservation? in
      guard days.count == 1, let prior = days.first,
        prior.activityLoad.problem(for: .activityLoad, allowPartial: false) == nil,
        let value = prior.activityLoad.value
      else { return nil }
      return BaselineObservation(date: date, input: prior.activityLoad, transformedValue: value)
    }.sorted { $0.date < $1.date }
    let maximum = observations.map(\.transformedValue).max()
    let referenceReason: ScoringMissingReason? =
      start == nil
      ? .invalidValue
      : maximum == nil ? .insufficientHistory : maximum == 0 ? .nonPositiveBaseline : nil
    let reference = LoadReference(
      windowStart: start, endExclusive: day.date, observations: observations,
      duplicateDates: duplicates, maximum: maximum, reason: referenceReason)
    let problem = day.activityLoad.problem(for: .activityLoad, allowPartial: false)
    let value = problem == nil ? day.activityLoad.value : nil
    var fraction: Double?
    if let value {
      if value == 0 {
        fraction = 0
      } else if let maximum, maximum > 0 {
        // Compare before dividing to avoid overflow, even for extreme finite totals.
        fraction = value >= maximum ? 1 : value / maximum
      }
    }
    return LoadResult(
      date: day.date, value: value, status: value == nil ? .unavailable : .available,
      input: day.activityLoad, ringFraction: fraction,
      ringReason: fraction == nil ? problem ?? referenceReason : nil,
      reference: reference,
      issues: problem.map { [ScoreIssue(metric: .activityLoad, reason: $0)] } ?? [], config: config)
  }
}
