import Foundation
import ScoringKit

/// Phase 4 consumes these values without reinterpreting availability or primary metrics.
nonisolated final class DialPresentation: Sendable, Equatable {
  let readiness: ReadinessDialPresentation
  let sleep: SleepDialPresentation
  let load: LoadDialPresentation

  init(day: ScoredDay) {
    readiness = ReadinessDialPresentation(result: day.readiness, context: day.readinessContext)
    sleep = SleepDialPresentation(result: day.sleep)
    load = LoadDialPresentation(result: day.load)
  }

  static func number(_ value: Double?) -> String {
    value.map { String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "–"
  }

  static func == (lhs: DialPresentation, rhs: DialPresentation) -> Bool {
    lhs === rhs
      || (lhs.readiness == rhs.readiness
        && lhs.sleep == rhs.sleep
        && lhs.load == rhs.load)
  }
}

/// Band names map to the existing configured colour tokens; Load always has its own colour.
nonisolated enum DialColour: Sendable, Equatable {
  case band(ScoreBand)
  case load
  case unavailable
}

nonisolated final class ReadinessDialPresentation: Sendable, Equatable {
  let summaryLabel = "Readiness"
  let detailAttribution = "Diel estimate"
  let result: ReadinessV2Result
  var version: String { result.version }
  var why: ReadinessV2Why { result.why }
  var status: ScoreStatus { result.status }
  /// Current readings, trends, references and sleep evidence remain visible when the score is missing.
  let context: ReadinessV2Context
  var value: Double? { result.value }
  var valueText: String { DialPresentation.number(value) }
  var ringFraction: Double? { value.map { $0 / 100 } }
  var colour: DialColour { result.band.map(DialColour.band) ?? .unavailable }

  init(
    result: ReadinessV2Result,
    context: ReadinessV2Context
  ) {
    self.result = result
    self.context = context
  }

  static func == (lhs: ReadinessDialPresentation, rhs: ReadinessDialPresentation) -> Bool {
    lhs === rhs
      || (lhs.result == rhs.result
        && lhs.context == rhs.context)
  }
}

nonisolated struct SleepDialPresentation: Sendable, Equatable {
  let summaryLabel = "Sleep"
  let detailAttribution = "Garmin Sleep Score"
  /// Includes primary provenance and independent duration and continuity components.
  let result: ScoreResult
  var value: Double? { result.value }
  var valueText: String { DialPresentation.number(value) }
  var ringFraction: Double? { value.map { $0 / 100 } }
  var colour: DialColour { result.band.map(DialColour.band) ?? .unavailable }
}

nonisolated struct LoadDialPresentation: Sendable, Equatable {
  let summaryLabel = "Load"
  let colour = DialColour.load
  /// Active all-day Load uses a 0–100 estimate and matching ring fraction.
  /// Results without `allDay` retain the legacy Garmin activity-load control.
  let result: LoadResult
  var value: Double? { result.value }
  var valueText: String { DialPresentation.number(value) }
  var ringFraction: Double? { result.ringFraction }
  var isTrackOnly: Bool { ringFraction == nil }
  var statusText: String? {
    result.allDay != nil
      ? (result.status == .provisional ? "So far" : nil) : result.isRestDay ? "Rest day" : nil
  }
}
