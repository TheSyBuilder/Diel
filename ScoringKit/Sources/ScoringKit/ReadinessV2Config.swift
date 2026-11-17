import Foundation

/// Frozen Diel product choices, not fitted coefficients or a validated recovery model.
public struct ReadinessV2Config: Sendable, Equatable, Codable {
  public let version: String
  public let referenceWindowDays = 60
  public let minimumReferenceSamples = 14
  public let trendWindowDays = 7
  public let minimumTrendSamples = 3
  public let sleepWindowDays = 3
  public let maximumDeviation = 3.0
  public var hrvTrendWeight: Double { isScaleRevision ? 0.35 : 0.40 }
  public let hrvAcuteWeight = 0.15
  public let restingHeartRateWeight = 0.25
  public let restingHeartRateTrendShare = 0.75
  public let restingHeartRateAcuteShare = 0.25
  public let sleepWeight = 0.20
  public let sleepAcuteWeight = 0.10
  public let sleepHistoryWeight = 0.15
  public var isScaleRevision: Bool { version == "readiness-v2.1" || isEWMARevision }
  public var isEWMARevision: Bool { version == "readiness-v2.2" }
  public let trendHalfLifeDays = 3.0
  public var normalizer: Double { isScaleRevision ? sqrt(0.24) : 1 }
  public let sleepDeficitPerDeviation = 0.10
  public let center = 50.0
  public let gain = 15.0
  public let directionalGate = 0.5
  public let extremeHighHRVGate = 2.0
  public let bands = ScoreBands()

  public init() { version = "readiness-v2" }

  private enum CodingKeys: String, CodingKey { case version }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let version = try container.decode(String.self, forKey: .version)
    guard ["readiness-v2", "readiness-v2.1", "readiness-v2.2"].contains(version) else {
      throw DecodingError.dataCorruptedError(
        forKey: .version, in: container, debugDescription: "Unknown readiness version")
    }
    self.version = version
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(version, forKey: .version)
  }
  private init(version: String) { self.version = version }
  public static let v2 = Self()
  // swift-format-ignore: AlwaysUseLowerCamelCase
  public static let v2_1 = Self(version: "readiness-v2.1")
  // swift-format-ignore: AlwaysUseLowerCamelCase
  public static let v2_2 = Self(version: "readiness-v2.2")

  /// Fixed final score bounds for both frozen versions.
  public var conservativeMinimum: Double { center - gain * maximumDeviation }
  public var conservativeMaximum: Double { center + gain * maximumDeviation }
  /// Original v2 sleep cannot award a bonus; v2.1 uses the full final bound.
  public var reachableMaximum: Double {
    isScaleRevision ? conservativeMaximum : center + gain * maximumDeviation * (1 - sleepWeight)
  }
}
