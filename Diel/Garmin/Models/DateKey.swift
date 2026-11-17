import Foundation

/// A Gregorian source calendar label, independent of timezone and timestamp interpretation.
nonisolated struct DateKey: RawRepresentable, Codable, Sendable, Hashable, Comparable {
  let rawValue: String

  enum ValidationError: Error {
    case invalidCalendarDate
  }

  init(_ value: String) throws {
    let bytes = Array(value.utf8)
    guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
      bytes.enumerated().allSatisfy({ index, byte in
        index == 4 || index == 7 || (48...57).contains(byte)
      }),
      let year = Int(value.prefix(4)), year > 0,
      let month = Int(value.dropFirst(5).prefix(2)), (1...12).contains(month),
      let day = Int(value.suffix(2))
    else { throw ValidationError.invalidCalendarDate }
    let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
    let days = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    guard (1...days[month - 1]).contains(day) else { throw ValidationError.invalidCalendarDate }
    rawValue = value
  }

  init?(rawValue: String) {
    guard let value = try? Self(rawValue) else { return nil }
    self = value
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let date = Self(rawValue: value) else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Invalid Gregorian date label")
    }
    self = date
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
