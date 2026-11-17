import Foundation

/// Gregorian calendar labels, independent of the user's timezone or UTC timestamps.
public struct ScoringDate: RawRepresentable, Sendable, Hashable, Comparable, Codable {
  public let rawValue: String

  public init?(rawValue: String) {
    let bytes = Array(rawValue.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
      bytes.enumerated().allSatisfy({ index, byte in
        index == 4 || index == 7 || (48...57).contains(byte)
      }),
      let year = Int(rawValue.prefix(4)), year > 0,
      let month = Int(rawValue.dropFirst(5).prefix(2)), (1...12).contains(month),
      let day = Int(rawValue.suffix(2))
    else { return nil }
    let leap = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...days[month - 1]).contains(day) else { return nil }
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

  public func adding(days: Int) -> Self? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = rawValue.split(separator: "-").compactMap { Int($0) }
    guard
      let date = calendar.date(
        from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
      let next = calendar.date(byAdding: .day, value: days, to: date)
    else { return nil }
    let components = calendar.dateComponents([.year, .month, .day], from: next)
    return Self(
      rawValue: String(
        format: "%04d-%02d-%02d", components.year!, components.month!, components.day!))
  }
}

public enum ScoringMissingReason: String, Sendable, Equatable, Codable {
  case missing, skipped, partial, insufficientHistory, invalidValue, dateMismatch, unverifiedUnit
  case zeroDispersion, nonPositiveBaseline, unverifiedCoverage, duplicateDay
}

public enum ScoringCoverage: String, Sendable, Equatable, Codable {
  case complete, partial, unknown
}

public enum ScoringDateProvenance: String, Sendable, Equatable, Codable {
  case recorded, inferredSleepNeed, unknown
}

public struct ScoringSource: Sendable, Equatable, Codable {
  /// The adapter preserves the upstream family name without importing its model enum.
  public let family: String
  public let responseID: UUID
  public let fetchedAt: Date

  public init(family: String, responseID: UUID, fetchedAt: Date) {
    self.family = family
    self.responseID = responseID
    self.fetchedAt = fetchedAt
  }
}

public struct ScoringMetric: Sendable, Equatable, Codable {
  public let value: Double?
  public let reason: ScoringMissingReason?
  public let coverage: ScoringCoverage
  public let dateProvenance: ScoringDateProvenance
  public let sources: [ScoringSource]
  public let coverageSources: [ScoringSource]

  public init(
    value: Double?, reason: ScoringMissingReason? = nil,
    coverage: ScoringCoverage = .unknown, dateProvenance: ScoringDateProvenance = .unknown,
    sources: [ScoringSource] = [], coverageSources: [ScoringSource] = []
  ) {
    self.value = value
    self.reason = reason
    self.coverage = coverage
    self.dateProvenance = dateProvenance
    self.sources = sources
    self.coverageSources = coverageSources
  }

  public static let missing = Self(value: nil, reason: .missing)
}

public enum ScoringMetricKind: String, Sendable, CaseIterable, Codable {
  case nightlyHRVMilliseconds, restingHeartRateBPM, sleepSeconds, awakeSeconds, sleepNeedSeconds
  case activityLoad, garminSleepScore
}

/// Already normalized units: milliseconds, bpm, seconds and Garmin's native load scalar.
/// The caller supplies one total per day, with list/detail activities already deduplicated.
public struct ScoringDayInput: Sendable, Equatable, Codable {
  public let date: ScoringDate
  public var nightlyHRVMilliseconds: ScoringMetric
  public var restingHeartRateBPM: ScoringMetric
  public var sleepSeconds: ScoringMetric
  public var awakeSeconds: ScoringMetric
  public var sleepNeedSeconds: ScoringMetric
  public var garminSleepScore: ScoringMetric
  public var activityLoad: ScoringMetric
  public var heartRateDay: LoadHeartRateDay?

  public init(
    date: ScoringDate, nightlyHRVMilliseconds: ScoringMetric = .missing,
    restingHeartRateBPM: ScoringMetric = .missing, sleepSeconds: ScoringMetric = .missing,
    awakeSeconds: ScoringMetric = .missing, sleepNeedSeconds: ScoringMetric = .missing,
    activityLoad: ScoringMetric = .missing, garminSleepScore: ScoringMetric = .missing,
    heartRateDay: LoadHeartRateDay? = nil
  ) {
    self.date = date
    self.nightlyHRVMilliseconds = nightlyHRVMilliseconds
    self.restingHeartRateBPM = restingHeartRateBPM
    self.sleepSeconds = sleepSeconds
    self.awakeSeconds = awakeSeconds
    self.sleepNeedSeconds = sleepNeedSeconds
    self.activityLoad = activityLoad
    self.garminSleepScore = garminSleepScore
    self.heartRateDay = heartRateDay
  }

  public subscript(metric: ScoringMetricKind) -> ScoringMetric {
    switch metric {
    case .nightlyHRVMilliseconds: nightlyHRVMilliseconds
    case .restingHeartRateBPM: restingHeartRateBPM
    case .sleepSeconds: sleepSeconds
    case .awakeSeconds: awakeSeconds
    case .sleepNeedSeconds: sleepNeedSeconds
    case .activityLoad: activityLoad
    case .garminSleepScore: garminSleepScore
    }
  }
}

extension ScoringMetric {
  func problem(for kind: ScoringMetricKind, allowPartial: Bool) -> ScoringMissingReason? {
    guard let value else { return reason ?? .missing }
    guard value.isFinite, value >= 0 else { return .invalidValue }
    if [.nightlyHRVMilliseconds, .restingHeartRateBPM, .sleepNeedSeconds].contains(kind), value == 0
    {
      return .invalidValue
    }
    if kind == .garminSleepScore, value > 100 { return .invalidValue }
    if let reason, reason != .partial { return reason }
    guard dateProvenance == .recorded else { return .dateMismatch }
    switch coverage {
    case .unknown: return .unverifiedCoverage
    case .partial:
      guard allowPartial else { return .partial }
      // An incomplete zero total cannot establish a genuinely zero activity day.
      if kind == .activityLoad, value == 0 { return .partial }
    case .complete:
      if reason == .partial { return .partial }
    }
    if kind == .activityLoad, coverageSources.isEmpty { return .unverifiedCoverage }
    return nil
  }
}
