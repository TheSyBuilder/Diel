import CryptoKit
import Foundation
import ScoringKit

/// The entire model boundary. No dates, scope identifiers, sources, DTOs or models enter it.
nonisolated struct BriefInput: Codable, Equatable, Sendable {
  struct Score: Codable, Equatable, Sendable {
    let value: Double?
    let displayValue: Double?
    let band: ScoreBand?
    let status: ScoreStatus
    let why: String
  }
  /// The qualitative Load state. `missing` means no HR data, `none` means under 10; the running
  /// number stays out. Earlier stored inputs used only the other raw values, so they still decode.
  enum LoadComparison: String, Codable, Sendable {
    case missing, none, lighter, usual, heavier, unknown
  }
  enum Disagreement: String, Codable, Sendable { case none, feelingLower, feelingHigher }
  let readiness: Score
  let sleep: Score
  let loadWhy: String
  let loadStatus: ScoreStatus
  let loadComparisonIsSameTime: Bool
  let sleepDurationMinutes: Int?
  let sleepNeedMinutes: Int?
  let sleepDifferenceMinutes: Int?
  let loadComparison: LoadComparison
  let rating: Int?
  let skipped: Bool
  let learning: Bool
  let missingReadiness: Bool
  let missingSleep: Bool
  let missingLoad: Bool
  let missingSleepComparison: Bool
  /// Short evidence labels only. No provenance or raw measurement records enter the model.
  var evidenceLimitations: [String]? = nil

  var disagreement: Disagreement {
    guard let rating, let band = readiness.band else { return .none }
    let feeling = rating <= 2 ? 0 : rating == 3 ? 1 : 2
    let readiness: Int
    switch band {
    case .lower: readiness = 0
    case .middle: readiness = 1
    case .upper: readiness = 2
    }
    return feeling == readiness ? .none : feeling < readiness ? .feelingLower : .feelingHigher
  }
  var hasMissingData: Bool {
    missingReadiness || missingSleep || missingLoad || missingSleepComparison
      || readiness.status == .provisional || sleep.status == .provisional
  }
  /// True when Readiness, Sleep or Load was missing in `prior` and has a value here. A score
  /// becoming missing, or a present value changing, never counts.
  func resolvesMissingScore(of prior: BriefInput) -> Bool {
    (prior.readiness.value == nil && readiness.value != nil)
      || (prior.sleep.value == nil && sleep.value != nil)
      || (prior.loadComparison == .missing && loadComparison != .missing)
  }
  var scoreFingerprint: String {
    // Only score and Load-state changes permit another generation. Answer edits, driver-only
    // updates and running Load within the same state do not.
    let values = [readiness.value, sleep.value]
    let bytes = ((try? JSONEncoder().encode(values)) ?? Data()) + Data(loadComparison.rawValue.utf8)
    return "brief-v4/" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  }
}

nonisolated enum BriefInputBuilder {
  static func make(day: ScoredDay?, history: [ScoredDay], checkIn: CheckInSnapshot) -> BriefInput {
    let presentation = day.map { TodayPresentation(day: $0, history: history) }
    func minutes(_ metric: ScoringKit.ScoringMetric?) -> Int? {
      guard let metric, metric.coverage == .complete, metric.reason == nil,
        let seconds = metric.value, seconds.isFinite, seconds >= 0
      else { return nil }
      return Int(exactly: (seconds / 60).rounded())
    }
    let durationMinutes = minutes(day?.input.sleepSeconds)
    let needMinutes = minutes(day?.input.sleepNeedSeconds).flatMap { $0 > 0 ? $0 : nil }
    let difference = durationMinutes.flatMap { duration in needMinutes.map { duration - $0 } }
    var limitations: [String] = []
    if let day {
      if day.readiness.value == nil {
        let reason = presentation?.dials.first?.reason ?? "Readiness unavailable"
        switch reason {
        case "No HRV last night": limitations.append("Last night's HRV missing")
        case "Learning your normal":
          limitations.append("Readiness unavailable while learning normal")
        case "No resting HR comparison": limitations.append("Resting HR comparison missing")
        default: limitations.append(reason)
        }
      }
      if day.readiness.status == .provisional {
        limitations.append(
          day.input.restingHeartRateBPM.coverage == .partial
            || day.input.restingHeartRateBPM.reason == .partial
            ? "Daily resting HR partial" : "Readiness evidence partial")
      }
      if day.sleep.value == nil {
        limitations.append("Sleep score unavailable")
      } else if day.sleep.status == .provisional {
        limitations.append("Sleep score partial")
      }
      if day.load.value == nil { limitations.append("Load unavailable") }
      if durationMinutes == nil {
        limitations.append(
          day.input.sleepSeconds.coverage == .partial || day.input.sleepSeconds.reason == .partial
            ? "Sleep duration partial" : "Sleep duration missing")
      }
      if needMinutes == nil {
        limitations.append(
          day.input.sleepNeedSeconds.coverage == .partial
            || day.input.sleepNeedSeconds.reason == .partial
            ? "Sleep need partial" : "Sleep need missing")
      }
    }
    let loadComparison: BriefInput.LoadComparison
    if let load = day?.load.value, load >= 10 {
      if let median = day?.load.allDay?.comparisonMedian {
        loadComparison =
          load.rounded() == median.rounded() ? .usual : load < median ? .lighter : .heavier
      } else {
        loadComparison = .unknown
      }
    } else if day?.load.value == nil {
      loadComparison = .missing
    } else {
      loadComparison = .none
    }
    return BriefInput(
      readiness: .init(
        value: day?.readiness.value, displayValue: day?.readiness.value?.rounded(),
        band: day?.readiness.band, status: day?.readiness.status ?? .unavailable,
        why: presentation?.dials.first?.reason ?? "Readiness unavailable"),
      sleep: .init(
        value: day?.sleep.value, displayValue: day?.sleep.value?.rounded(), band: day?.sleep.band,
        status: day?.sleep.status ?? .unavailable,
        why: presentation?.dials.last?.reason ?? "Sleep score unavailable"),
      loadWhy: presentation?.dials.dropFirst().first?.reason ?? "Load unavailable",
      loadStatus: day?.load.status ?? .unavailable,
      loadComparisonIsSameTime: day?.load.allDay?.comparisonIsSameTime ?? false,
      sleepDurationMinutes: durationMinutes, sleepNeedMinutes: needMinutes,
      sleepDifferenceMinutes: difference, loadComparison: loadComparison,
      rating: checkIn.rating, skipped: checkIn.skipped,
      learning: day.map { ReadinessLearningHistory(day: $0, history: history).isLearning } ?? false,
      missingReadiness: day?.readiness.value == nil, missingSleep: day?.sleep.value == nil,
      missingLoad: day?.load.value == nil, missingSleepComparison: difference == nil,
      evidenceLimitations: limitations)
  }
}
