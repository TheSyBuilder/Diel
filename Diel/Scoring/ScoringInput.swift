import Foundation
import ScoringKit

/// Input values carry availability separately from their number. A measured zero stays zero.
nonisolated enum ScoringMissingReason: String, Sendable, Equatable {
  case missing, skipped, partial, insufficientHistory, invalidValue, dateMismatch, unverifiedUnit
}

nonisolated enum ScoringCoverage: String, Sendable, Equatable {
  case complete, partial, unknown
}

nonisolated enum ScoringDateProvenance: String, Sendable, Equatable {
  case recorded, inferredSleepNeed, unknown
}

nonisolated struct ScoringSource: Sendable, Equatable {
  let family: GarminPayload.Family
  let responseID: UUID
  let fetchedAt: Date
}

nonisolated struct ScoringMetric: Sendable, Equatable {
  let value: Double?
  let reason: ScoringMissingReason?
  let coverage: ScoringCoverage
  let dateProvenance: ScoringDateProvenance
  /// Responses supplying the selected metric values.
  let sources: [ScoringSource]
  /// Responses proving collection coverage, independently of value selection.
  let coverageSources: [ScoringSource]
}

/// Units are explicit. Training load retains Garmin's scalar; it is not duration or calories.
nonisolated struct ScoringDayInput: Sendable, Equatable {
  let date: DateKey
  let nightlyHRVMilliseconds: ScoringMetric
  let restingHeartRateBPM: ScoringMetric
  let sleepSeconds: ScoringMetric
  let awakeSeconds: ScoringMetric
  let sleepNeedSeconds: ScoringMetric
  let activityLoad: ScoringMetric
  let garminSleepScore: ScoringMetric
  var heartRateDay: LoadHeartRateDay? = nil
}

/// An undated rejected record is never inserted as a measured day.
nonisolated struct GarminSkippedSleep: Sendable, Equatable {
  let candidateDate: DateKey?
  let provenance: ScoringDateProvenance
  let source: ScoringSource
}

nonisolated struct GarminActivityCoverage: Sendable {
  let dates: ClosedRange<DateKey>
  let fetchedAt: Date
  let completePagination: Bool
  let reason: ScoringMissingReason?
  let activityIDsByDate: [DateKey: Set<Int64>]
  let sources: [ScoringSource]
}

/// Actor-produced values only. No raw JSON or SwiftData objects cross the scoring boundary.
nonisolated struct GarminScoringSnapshot: Sendable {
  let revision: CredentialRevision
  let days: [GarminDaySnapshot]
  let activities: [GarminActivitySnapshot]
  let activityCoverage: [GarminActivityCoverage]
  let skippedSleep: [GarminSkippedSleep]
  let sourceMetadata: [UUID: ScoringSource]
}

extension ScoringDayInput {
  /// The package accepts the same Gregorian day labels; no instant conversion is involved.
  nonisolated var scoringInput: ScoringKit.ScoringDayInput {
    ScoringKit.ScoringDayInput(
      date: ScoringKit.ScoringDate(rawValue: date.rawValue)!,
      nightlyHRVMilliseconds: nightlyHRVMilliseconds.scoringMetric,
      restingHeartRateBPM: restingHeartRateBPM.scoringMetric,
      sleepSeconds: sleepSeconds.scoringMetric, awakeSeconds: awakeSeconds.scoringMetric,
      sleepNeedSeconds: sleepNeedSeconds.scoringMetric, activityLoad: activityLoad.scoringMetric,
      garminSleepScore: garminSleepScore.scoringMetric, heartRateDay: heartRateDay)
  }
}

extension ScoringMetric {
  nonisolated var scoringMetric: ScoringKit.ScoringMetric {
    ScoringKit.ScoringMetric(
      value: value, reason: reason.map { ScoringKit.ScoringMissingReason(rawValue: $0.rawValue)! },
      coverage: ScoringKit.ScoringCoverage(rawValue: coverage.rawValue)!,
      dateProvenance: ScoringKit.ScoringDateProvenance(rawValue: dateProvenance.rawValue)!,
      sources: sources.map(\.scoringSource), coverageSources: coverageSources.map(\.scoringSource))
  }
}

extension ScoringSource {
  nonisolated var scoringSource: ScoringKit.ScoringSource {
    ScoringKit.ScoringSource(family: family.rawValue, responseID: responseID, fetchedAt: fetchedAt)
  }
}
