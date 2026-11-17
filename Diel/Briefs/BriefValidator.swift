import Foundation

/// The model may paraphrase evidence, but cannot add measurements or medical interpretations.
nonisolated enum BriefValidator {
  static func isValid(_ brief: Brief, for input: BriefInput) -> Bool {
    let text = "\(brief.headline) \(brief.body)"
    let lower = text.precomposedStringWithCompatibilityMapping.lowercased()
      .replacingOccurrences(of: "\u{2010}", with: "-")
      .replacingOccurrences(of: "\u{2011}", with: "-")
      .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    guard !brief.headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      !brief.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      words(brief.headline) <= 8, words(brief.body) <= 60,
      sentenceCount(brief.body) <= 2,
      !text.contains("!"), !text.contains("！"),
      !containsAny(
        lower,
        [
          "diagnos", "disease", "illness", "maladapt", "overtrain", "fatigue", "infection",
          "sick", "medical", "injur", "treatment", "cure", "disorder", "you should", "you must",
          "try to", "remember to", "make sure", "stay hydrated", "take a rest", "take it easy",
          "push yourself", "recommend", "consider ", "listen to your body", "healthy", "unhealthy",
          "recover", "burnout", "immune", "dehydrat",
          "ewma", "half-life", "half life", "reference", "series points", "readings needed",
          "native units", "complete collection", "date-matched", "date matched", "source date",
          "source id", "sourceid", "bundled", "sample count", "credential", "api key",
          "diel estimate", "diel's estimate", "provisional", "provenance", "sourcedate", "morning",
          "hypertens", "hypotens", "diabet", "apnea", "apnoea", "arrhythm", "fibrillation",
          "tachycard", "bradycard", "heart attack", "stroke", "anemia", "anaemia", "insomnia",
          "depression", "anxiety", "syndrome", "inflamm", "cardiac", "blood pressure",
          "pattern suggests", "signs of", "symptoms of", "risk of", "at risk", "consistent with",
          "suggestive of", "points to", "indicates", "you have", "you may have", "you could have",
        ]),
      !claimsOvernightRestingHeartRate(lower), !statesLoadNumber(lower),
      !NumberEvidence.hasLongMinuteDuration(lower),
      NumberEvidence.accepts(text, input: input)
    else { return false }
    if input.learning {
      guard containsAny(lower, ["learning", "taking shape", "limited context"]) else {
        return false
      }
    }
    if input.hasMissingData {
      guard containsAny(lower, ["missing", "partial", "unavailable", "limited", "incomplete"])
      else { return false }
      // A limitation must not erase known scores, as the old generic fallback did.
      let mentioned = NumberEvidence.numbers(in: text) ?? []
      for (name, value) in [
        ("readiness", input.readiness.displayValue),
        ("sleep", input.sleep.displayValue),
      ] {
        if let value {
          guard lower.contains(name), mentioned.contains(value) else { return false }
        }
      }
    }
    if input.readiness.value == nil && input.sleep.value == nil && input.missingLoad {
      let durations = NumberEvidence.numbersIncludingDurationTotals(in: text) ?? []
      let knownSleep = [
        input.sleepDurationMinutes, input.sleepNeedMinutes,
        input.sleepDifferenceMinutes.flatMap { $0 < 0 ? -$0 : nil },
      ].compactMap { $0 }
      if !knownSleep.isEmpty {
        guard lower.contains("sleep"), knownSleep.allSatisfy({ durations.contains(Double($0)) })
        else { return false }
      }
    }
    if input.disagreement != .none {
      guard lower.contains("feel") || lower.contains("felt"), lower.contains("readiness"),
        containsAny(
          lower, ["than readiness", "differs", "different", "doesn't match", "does not match"])
      else { return false }
    }
    return true
  }

  static func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }

  private static func sentenceCount(_ text: String) -> Int {
    // A decimal point is part of a number, not another sentence.
    let expression = try! NSRegularExpression(pattern: #"(?<!\d)[.!?]+|[.!?]+(?!\d)"#)
    let count = expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    return max(1, count + (text.last.map { ".!?".contains($0) } == true ? 0 : 1))
  }

  private static func claimsOvernightRestingHeartRate(_ text: String) -> Bool {
    let rate = #"(?:resting\s+(?:heart\s+rate|hr)|rhr)"#
    let night = #"(?:overnight|nighttime|night[- ]time|nocturnal)"#
    return text.range(
      of: "\\b\(night)\\s+\(rate)\\b|\\b\(rate)\\s+(?:from\\s+)?(?:the\\s+)?\(night)\\b",
      options: .regularExpression) != nil
  }

  /// Load is qualitative in the brief. Any number in the few words after "load", within the
  /// same clause, states the running value, which would change through the day.
  private static func statesLoadNumber(_ text: String) -> Bool {
    let expression = try! NSRegularExpression(pattern: #"\bload\b([^.;,!?]*)"#)
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains {
      guard let range = Range($0.range(at: 1), in: text) else { return false }
      let following = text[range].split(whereSeparator: \.isWhitespace).prefix(4)
        .joined(separator: " ")
      return NumberEvidence.numbers(in: following).map { !$0.isEmpty } ?? true
    }
  }

  private static func containsAny(_ text: String, _ values: [String]) -> Bool {
    values.contains { text.contains($0) }
  }
}

nonisolated enum NumberEvidence {
  private static let small: [String: Double] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
    "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12,
    "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
    "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
    "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    "half": 0.5, "quarter": 0.25, "dozen": 12,
    "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
  ]
  private static let scales: [String: Double] = [
    "hundred": 100, "thousand": 1000, "million": 1_000_000,
    "billion": 1_000_000_000, "trillion": 1_000_000_000_000,
  ]

  static func hasLongMinuteDuration(_ text: String) -> Bool {
    let numberWords = (Array(small.keys) + Array(scales.keys) + ["and", "point"])
      .map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    let digits =
      #"[-+]?(?:(?:\d{1,3}(?:[,\u00a0\u202f ]\d{3})+)|\d+|(?=\.\d))(?:[.,]\d+)?(?:e[-+]?\d+)?"#
    let expression = try! NSRegularExpression(
      pattern:
        "(?:\(digits)|\\b(?:\(numberWords))(?:[ -]+(?:\(numberWords)))*)\\s*(?:-\\s*)?(?:minutes?|mins?|m)\\b"
    )
    return expression.matches(in: text, range: NSRange(text.startIndex..., in: text)).contains {
      guard let range = Range($0.range, in: text), let values = numbers(in: String(text[range]))
      else { return false }
      return values.contains { abs($0) >= 60 }
    }
  }

  static func accepts(_ text: String, input: BriefInput) -> Bool {
    let supplied =
      [
        input.readiness.value, input.readiness.displayValue, input.sleep.value,
        input.sleep.displayValue,
        input.sleepDurationMinutes.map(Double.init),
        input.sleepNeedMinutes.map(Double.init),
        input.sleepDifferenceMinutes.map { Double(abs($0)) },
        input.rating.map(Double.init),
      ].compactMap { $0 }
      + (numbers(in: input.readiness.why) ?? []) + (numbers(in: input.sleep.why) ?? [])
      + (numbers(in: input.loadWhy) ?? [])
    guard let mentioned = numbersIncludingDurationTotals(in: text) else { return false }
    return mentioned.allSatisfy { number in
      supplied.contains(number)
    }
  }

  /// Keep hours/minutes together when checking that measured sleep evidence was retained.
  static func numbersIncludingDurationTotals(in text: String) -> [Double]? {
    // Ground hour/minute display forms in the supplied total minutes, not loose digit parts.
    let durations = try! NSRegularExpression(pattern: #"\b(\d+)h(?:\s+(\d+)m)?\b"#)
    var normalized = text
    for match in durations.matches(in: text, range: NSRange(text.startIndex..., in: text))
      .reversed()
    {
      guard let whole = Range(match.range, in: text),
        let hoursRange = Range(match.range(at: 1), in: text),
        let hours = Int(text[hoursRange]), hours <= Int.max / 60
      else { return nil }
      let minutes = Range(match.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
      guard minutes < 60, hours * 60 <= Int.max - minutes else { return nil }
      normalized.replaceSubrange(whole, with: String(hours * 60 + minutes))
    }
    return numbers(in: normalized)
  }

  /// Recognises digits, grouping/decimal variants, scientific notation and English number phrases.
  static func numbers(in text: String) -> [Double]? {
    let normalized = text.precomposedStringWithCompatibilityMapping.lowercased()
      .map { character -> String in
        if let digit = character.wholeNumberValue, (0...9).contains(digit) { return String(digit) }
        return String(character)
      }.joined()
      .replacingOccurrences(of: "−", with: "-")
      .replacingOccurrences(of: "‐", with: "-")
      .replacingOccurrences(of: "‑", with: "-")
      .replacingOccurrences(of: "–", with: "-")
      .replacingOccurrences(of: "⁄", with: "/")
      .replacingOccurrences(of: "∕", with: "/")
      .replacingOccurrences(
        of: #"\b(?:minus|negative)\s+(?=[0-9.])"#, with: "-", options: .regularExpression)
    if normalized.range(of: #"\d\s*/\s*\d"#, options: .regularExpression) != nil { return nil }
    let digits = try! NSRegularExpression(
      pattern:
        #"[-+]?(?:(?:\d{1,3}(?:[,\u00a0\u202f ]\d{3})+)|\d+|(?=\.\d))(?:[.,]\d+)?(?:e[-+]?\d+)?"#)
    var values: [Double] = []
    for match in digits.matches(
      in: normalized, range: NSRange(normalized.startIndex..., in: normalized))
    {
      guard let range = Range(match.range, in: normalized) else { return nil }
      var number = String(normalized[range]).replacingOccurrences(of: " ", with: "")
        .replacingOccurrences(of: "\u{00a0}", with: "")
        .replacingOccurrences(of: "\u{202f}", with: "")
      if number.contains(",") {
        let groups = number.split(separator: ",")
        if groups.dropFirst().allSatisfy({ $0.prefix(while: \.isNumber).count == 3 }) {
          number = number.replacingOccurrences(of: ",", with: "")
        } else {
          number = number.replacingOccurrences(of: ",", with: ".")
        }
      }
      guard let value = Double(number), value.isFinite else { return nil }
      values.append(value)
    }
    let wordTokens = try! NSRegularExpression(pattern: #"[a-z]+|[^\sa-z-]+"#)
    let tokens = wordTokens.matches(
      in: normalized, range: NSRange(normalized.startIndex..., in: normalized)
    )
    .compactMap { Range($0.range, in: normalized).map { String(normalized[$0]) } }
    // Reject unsupported scale words instead of silently reading only their small prefix.
    for token in tokens where scales[token] == nil {
      if token.contains("illion")
        || ["hundreds", "thousands", "hundredth", "thousandth", "googol", "infinity"].contains(
          token)
      {
        return nil
      }
    }
    // Fractions/dozen compounds need grammar beyond additive cardinal numbers. Reject them
    // conservatively rather than ground a different quantity in their individual words.
    for index in tokens.indices {
      let token = tokens[index]
      if ["halves", "quarters", "dozens"].contains(token) { return nil }
      guard ["half", "quarter", "dozen"].contains(token) else { continue }
      var before = index - 1
      while before >= 0 && ["a", "an", "and"].contains(tokens[before]) { before -= 1 }
      var after = index + 1
      while after < tokens.count && ["a", "an", "and"].contains(tokens[after]) { after += 1 }
      if before >= 0
        && (small[tokens[before]] != nil || scales[tokens[before]] != nil
          || tokens[before].contains(where: \.isNumber))
        || after < tokens.count
          && (small[tokens[after]] != nil || scales[tokens[after]] != nil
            || tokens[after].contains(where: \.isNumber))
      {
        return nil
      }
    }
    var index = 0
    while index < tokens.count {
      let signed = tokens[index] == "minus" || tokens[index] == "negative"
      guard
        small[tokens[index]] != nil || scales[tokens[index]] != nil
          || signed && index + 1 < tokens.count && small[tokens[index + 1]] != nil
      else {
        index += 1
        continue
      }
      let sign = signed ? -1.0 : 1.0
      if signed { index += 1 }
      var total = 0.0
      var group = 0.0
      var decimal = ""
      var afterPoint = false
      var hasScale = false
      var lastLargeScale = Double.infinity
      while index < tokens.count {
        let token = tokens[index]
        if let value = small[token] {
          if afterPoint {
            guard value < 10, value.rounded() == value else { return nil }
            decimal += String(Int(value))
          } else {
            group += value
          }
        } else if let scale = scales[token] {
          guard !afterPoint else { return nil }
          hasScale = true
          if scale == 100 {
            group = max(1, group) * scale
          } else {
            guard scale < lastLargeScale else { return nil }
            lastLargeScale = scale
            total += max(1, group) * scale
            group = 0
          }
        } else if token == "point" {
          afterPoint = true
        } else if token == "and", hasScale,
          index + 1 < tokens.count, small[tokens[index + 1]] != nil
        {
          // Only the conventional "one hundred and five" connector belongs to the number.
        } else {
          break
        }
        index += 1
      }
      if afterPoint {
        guard !decimal.isEmpty, let fraction = Double("0.\(decimal)") else { return nil }
        group += fraction
      }
      values.append(sign * (total + group))
    }
    return values
  }
}
