#if DEBUG
  import Foundation
  import ScoringKit

  /// Fixture-only exports contain evidence, never application logs or persisted scores.
  nonisolated enum ScoringReviewReport {
    static func markdown(_ days: [ScoredDay]) -> String {
      let activeVersion = days.first?.readiness.version ?? ReadinessV2Config.v2_2.version
      let controlVersion = days.first?.readinessV21.version ?? ReadinessV2Config.v2_1.version
      var lines = [
        "# Diel store-backed readiness comparison", "",
        "GarminStore → normalized inputs → ScoringKit. Calendar gaps remain missing. Every reference excludes the score date and future dates. Fixture history is shorter than 60 days, so this is a warmup comparison rather than a full-reference validation.",
        "Frozen \(controlVersion) uses seven-calendar-day means and empirical sleep adequacy SDs. Active \(activeVersion) uses causal normalized EWMA trends with a three-calendar-day half-life and a separate minimum-three-in-seven eligibility gate. Its preceding-60-day EWMA reference retains older decayed source inputs and requires 14 qualifying series dates. Acute physiological references remain daily readings.",
        "Both revisions use weights 0.35/0.15/0.25/0.10/0.15, center 50, gain 15, normalizer sqrt(0.24), physiological caps [-3,+3], sleep caps [-3,+1] and a final 5...95 bound. Active sleep uses (adequacy - 1) / 0.10 fixed need-relative units with no historical sleep gate. Family totals are signed point sums; points precede the final bound. No date-specific output target is imposed.",
        "Original readiness-v2 and both v1 controls are frozen. Daily RHR is Garmin daily RHR. Sleep remains Garmin's optional primary score. Load remains native Garmin units with its independent 28-day maximum. Source timestamps are fetch times. Human believability review remains pending.",
        "",
        "| Date | Original v1 gain20 / v1 gain15 | Original v2 raw / rounded / band / status | \(controlVersion) raw / rounded / band / status | \(activeVersion) raw / rounded / band / status | v2.1 points H / acute H / R / acute sleep / history | v2.2 points H / acute H / R / acute sleep / history | v2.1 family H / R / sleep | v2.2 family H / R / sleep | v2.1 unclamped / clamp adjustment | v2.2 unclamped / clamp adjustment | Original v2 why / causes | v2.1 why / causes | v2.2 why / causes |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
      ]
      for day in days {
        let old = day.readinessV21
        let active = day.readiness
        lines.append(
          "| \(day.input.date.rawValue) | \(number(day.readinessOriginalV1.value)) / \(number(day.readinessV1.value)) | \(score(day.readinessOriginalV2)) | \(score(old)) | \(score(active)) | \(points(old)) | \(points(active)) | \(families(old).map { number($0) }.joined(separator: " / ")) | \(families(active).map { number($0) }.joined(separator: " / ")) | \(number(old.unclampedValue)) / \(number(old.finalClampAdjustment)) | \(number(active.unclampedValue)) / \(number(active.finalClampAdjustment)) | \(why(day.readinessOriginalV2)) | \(why(old)) | \(why(active)) |"
        )
      }
      lines += [
        "", "## Summary", "",
        "| Version | Raw min / max | Displayed min / max | Lower / middle / upper | Available / provisional / unavailable | Raw bound hits 5 / 95 | Displayed bound hits 5 / 95 |",
        "|---|---|---|---|---|---|---|",
      ]
      for (name, results) in [
        ("Original v2", days.map(\.readinessOriginalV2)),
        (controlVersion, days.map(\.readinessV21)), (activeVersion, days.map(\.readiness)),
      ] {
        let values = results.compactMap(\.value)
        let display = results.compactMap(\.roundedValue)
        let bands = [ScoreBand.lower, .middle, .upper].map { band in
          String(results.filter { $0.band == band }.count)
        }.joined(separator: " / ")
        let states = [ScoreStatus.available, .provisional, .unavailable].map { status in
          String(results.filter { $0.status == status }.count)
        }.joined(separator: " / ")
        lines.append(
          "| \(name) | \(number(values.min())) / \(number(values.max())) | \(number(display.min())) / \(number(display.max())) | \(bands) | \(states) | \(values.filter { $0 <= 5 }.count) / \(values.filter { $0 >= 95 }.count) | \(display.filter { $0 <= 5 }.count) / \(display.filter { $0 >= 95 }.count) |"
        )
      }
      let eligibility = days.filter {
        ($0.readiness.value != nil) != ($0.readinessV21.value != nil)
      }
      let restored = eligibility.filter { $0.readiness.value != nil }
      let lost = eligibility.filter { $0.readiness.value == nil }
      let bandChanges = days.filter {
        $0.readiness.value != nil && $0.readinessV21.value != nil
          && $0.readiness.band != $0.readinessV21.band
      }
      lines += [
        "",
        "Eligibility changes versus frozen v2.1: \(eligibility.count). Shared eligible band changes: \(bandChanges.count).",
        "Restored dates: \(dateList(restored)). Lost dates: \(dateList(lost)).",
        "The 14-point trend-reference gate is unchanged. The rows show which dates return; removing the sleep history gate does not guarantee that every formerly blocked date becomes eligible.",
        "", "## Reference and source evidence", "",
      ]
      for day in days {
        lines.append("### \(day.input.date.rawValue)")
        for result in [day.readinessV21, day.readiness] {
          let selected = result.why.evidence.selectedPart
          let selection =
            result.why.evidence.selectedFamily.map { $0.rawValue } ?? "component control"
          let part =
            selected.map {
              "\($0.component.rawValue).\($0.subterm?.rawValue ?? "whole") \(number($0.pointContribution)) points"
            } ?? result.why.contributor?.rawValue ?? "none"
          let clipped = result.components.flatMap { component in
            (component.deviation.wasClipped ? [component.kind.rawValue] : [])
              + component.subterms.filter { $0.deviation.wasClipped }.map {
                "\(component.kind.rawValue).\($0.kind.rawValue)"
              }
          }
          lines.append(
            "\(result.version): \(referenceLine(result)); selected family \(selection), part \(part); clipped \(clipped.isEmpty ? "none" : clipped.joined(separator: ", ")); \(why(result))."
          )
        }
      }
      lines += [
        "",
        "Full precision JSON retains normalized inputs, all four controls and active results, each reference distribution and its windows or EWMA series, sample SD, exclusions, source and coverage provenance, unclamped points, family totals, final clamp adjustment and why evidence.",
        "",
      ]
      return lines.joined(separator: "\n")
    }

    static func markdown(_ days: [ScoredDay], history: [ScoringKit.ScoringDayInput]) -> String {
      markdown(days)
    }

    /// Includes October 29 as the anchor; deltas always use the preceding calendar day.
    static func trendDeltas(_ days: [ScoredDay]) -> String {
      let rows = Dictionary(uniqueKeysWithValues: days.map { ($0.input.date.rawValue, $0) })
      var lines = [
        "# HRV trend changes, October 30 to November 3", "",
        "October 29 is the anchor. Each delta subtracts the preceding calendar day's computed value. A missing current or preceding value remains missing. Score points use the actual normalized HRV trend contribution, including its cap; no smoothing outcome is assumed.",
        "",
        "| Date | Version | Trend ms | Δ ms | Trend ln(ms) | Δ ln(ms) | Reference ln mean | Reference ln sample SD | Raw z | Δ raw z | Clipped z | Δ clipped z | Score points | Δ score points |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
      ]
      for label in [
        "2026-10-29", "2026-10-30", "2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03",
      ] {
        guard let day = rows[label] else { continue }
        let priorLabel = day.input.date.adding(days: -1)?.rawValue
        let prior = priorLabel.flatMap { rows[$0] }
        for (result, previous) in [
          (day.readinessV21, prior?.readinessV21), (day.readiness, prior?.readiness),
        ] {
          let component = result.components.first { $0.kind == .hrvTrend }
          let previousComponent = previous?.components.first { $0.kind == .hrvTrend }
          let anchor = label == "2026-10-29"
          let trend = result.context.hrvTrend
          let evidence = result.why.evidence
          let deltas = [
            difference(trend.value, previous?.context.hrvTrend.value),
            difference(trend.transformedMean, previous?.context.hrvTrend.transformedMean),
            difference(component?.deviation.rawValue, previousComponent?.deviation.rawValue),
            difference(component?.deviation.value, previousComponent?.deviation.value),
            difference(component?.pointContribution, previousComponent?.pointContribution),
          ].map { anchor ? "anchor" : number($0) }
          lines.append(
            "| \(label) | \(result.version) | \(number(trend.value)) | \(deltas[0]) | \(number(trend.transformedMean)) | \(deltas[1]) | \(number(evidence.hrvReferenceLogMean)) | \(number(evidence.hrvReferenceLogSampleSD)) | \(number(component?.deviation.rawValue)) | \(deltas[2]) | \(number(component?.deviation.value)) | \(deltas[3]) | \(number(component?.pointContribution)) | \(deltas[4]) |"
          )
        }
      }
      return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ days: [ScoredDay], history: [ScoringKit.ScoringDayInput]) throws -> Data {
      let rows = days.map { day -> [String: Any] in
        [
          "date": day.input.date.rawValue, "activeVersion": day.readiness.version,
          "input": evidence(day.input),
          "originalV1Gain20": evidence(day.readinessOriginalV1),
          "currentV1Gain15": evidence(day.readinessV1),
          "v1Context": evidence(day.readinessV1Context),
          "originalV2": resultEvidence(day.readinessOriginalV2),
          "v2_1": resultEvidence(day.readinessV21),
          "v2_2": resultEvidence(day.readiness),
          "sleepDial": evidence(day.sleep), "nativeLoad": evidence(day.load),
        ]
      }
      let payload: [String: Any] = [
        "contract":
          "\(days.first?.readiness.version ?? ReadinessV2Config.v2_2.version); original v2, v2.1 and v1 controls frozen; no coefficient fitting",
        "limitations":
          "Fixture history is shorter than 60 days. Human believability review is pending.",
        "history": evidence(history),
        "statistics": [
          "calendarRows": days.count,
          "originalV2": statistics(days.map(\.readinessOriginalV2)),
          "v2_1": statistics(days.map(\.readinessV21)),
          "v2_2": statistics(days.map(\.readiness)),
          "eligibilityChanges": days.filter {
            ($0.readiness.value != nil) != ($0.readinessV21.value != nil)
          }.map(\.input.date.rawValue),
          "restoredDates": days.filter {
            $0.readiness.value != nil && $0.readinessV21.value == nil
          }.map(\.input.date.rawValue),
          "lostDates": days.filter {
            $0.readiness.value == nil && $0.readinessV21.value != nil
          }.map(\.input.date.rawValue),
          "statusChanges": days.filter { $0.readiness.status != $0.readinessV21.status }
            .map(\.input.date.rawValue),
        ],
        "rows": rows,
      ]
      return try JSONSerialization.data(
        withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func points(_ result: ReadinessV2Result) -> String {
      result.components.map {
        number(
          $0.pointContribution
            ?? $0.weightedContribution.map {
              result.config.gain * $0 / result.config.normalizer
            })
      }.joined(separator: " / ")
    }

    private static func families(_ result: ReadinessV2Result) -> [Double?] {
      [
        [ReadinessV2ComponentKind.hrvTrend, .hrvAcute], [.restingHeartRate],
        [.sleep, .sleepAcute, .sleepHistory],
      ].map { kinds in
        let components = result.components.filter { kinds.contains($0.kind) }
        let points = components.map { component in
          component.pointContribution
            ?? component.weightedContribution.map {
              result.config.gain * $0 / result.config.normalizer
            }
        }
        guard !points.isEmpty, points.allSatisfy({ $0 != nil }) else { return nil }
        return points.compactMap { $0 }.reduce(0, +)
      }
    }

    private static func why(_ result: ReadinessV2Result) -> String {
      let causes = result.issues.map { "\($0.metric?.rawValue ?? "score"):\($0.reason.rawValue)" }
      return
        "\(result.why.reasonCode.rawValue): \(result.why.line); \(causes.joined(separator: ", "))"
    }

    private static func referenceLine(_ result: ReadinessV2Result) -> String {
      let context = result.context
      let why = result.why.evidence
      let referenceCounts: String
      if let ewma = context.ewmaEvidence {
        referenceCounts =
          "EWMA reference HRV/RHR counts \(ewma.hrvTrendReference.sampleCount)/\(ewma.rhrTrendReference.sampleCount), required 14; recent complete HRV/RHR counts \(context.hrvTrend.ewma?.recentSampleCount ?? 0)/\(context.restingHeartRateTrend.ewma?.recentSampleCount ?? 0), required 3"
      } else if let scale = context.scaleEvidence {
        referenceCounts =
          "rolling reference HRV/RHR counts \(scale.hrvTrendReference.sampleCount)/\(scale.rhrTrendReference.sampleCount), required 14; sleep reference nightly/three-night counts \(scale.acuteSleepReference.sampleCount)/\(scale.historySleepReference.sampleCount), required 14"
      } else {
        referenceCounts = "daily physiological references"
      }
      return
        "\(referenceCounts); acute HRV count \(context.latestHRV.reference.sampleCount), daily RHR count \(context.restingHeartRate.reference.sampleCount); HRV trend reference ln mean/SD \(number(why.hrvReferenceLogMean))/\(number(why.hrvReferenceLogSampleSD)); RHR trend reference mean/SD \(number(why.rhrReferenceMeanBPM))/\(number(why.rhrReferenceSampleSDBPM)); complete sleep pairs \(context.sleep.nightCount)/\(context.sleep.requiredNightCount)"
    }

    private static func dateList(_ days: [ScoredDay]) -> String {
      days.isEmpty ? "none" : days.map(\.input.date.rawValue).joined(separator: ", ")
    }

    private static func difference(_ current: Double?, _ previous: Double?) -> Double? {
      guard let current, let previous else { return nil }
      return current - previous
    }

    private static func resultEvidence(_ result: ReadinessV2Result) -> [String: Any] {
      [
        "evidence": evidence(result), "version": result.version,
        "value": optional(result.value), "status": result.status.rawValue,
        "band": result.band.map { $0.rawValue as Any } ?? NSNull(),
        "formula": [
          "center": result.config.center, "gain": result.config.gain,
          "normalizer": result.config.normalizer,
          "componentWeights": result.components.map(\.weight),
          "minimum": result.config.conservativeMinimum,
          "maximum": result.config.reachableMaximum,
        ],
        "referenceSummary": referenceSummary(result.context),
        "familyPointTotals": Dictionary(
          uniqueKeysWithValues:
            zip(["HRV", "RHR", "Sleep"], families(result).map { optional($0) })),
        "why": evidence(result.why),
        "roundedValue": optional(result.roundedValue),
        "unclampedValue": optional(result.unclampedValue),
        "finalClampAdjustment": optional(result.finalClampAdjustment),
        "weightedDeviation": optional(result.weightedDeviation),
        "components": result.components.map { component in
          [
            "evidence": evidence(component),
            "weightedQ": optional(component.weightedContribution),
            "scorePoints": optional(
              component.pointContribution
                ?? component.weightedContribution.map {
                  result.config.gain * $0 / result.config.normalizer
                }),
            "clipped": component.deviation.wasClipped,
            "subtermClipped": component.subterms.map { $0.deviation.wasClipped },
          ] as [String: Any]
        },
      ]
    }

    private static func referenceSummary(_ context: ReadinessV2Context) -> [String: Any] {
      var result: [String: Any] = [
        "acuteHRV": ["count": context.latestHRV.reference.sampleCount],
        "acuteRHR": ["count": context.restingHeartRate.reference.sampleCount],
        "currentHRVTrend": ["count": context.hrvTrend.sampleCount],
        "currentRHRTrend": ["count": context.restingHeartRateTrend.sampleCount],
        "currentSleepHistory": ["count": context.sleep.nightCount],
      ]
      if let scale = context.scaleEvidence {
        result["rollingHRV"] = ["count": scale.hrvTrendReference.sampleCount]
        result["rollingRHR"] = ["count": scale.rhrTrendReference.sampleCount]
        result["nightlySleep"] = ["count": scale.acuteSleepReference.sampleCount]
        result["exactThreeSleep"] = ["count": scale.historySleepReference.sampleCount]
      }
      if let ewma = context.ewmaEvidence {
        result["ewmaHRV"] = [
          "count": ewma.hrvTrendReference.sampleCount,
          "requiredCount": ewma.hrvTrendReference.requiredSampleCount,
        ]
        result["ewmaRHR"] = [
          "count": ewma.rhrTrendReference.sampleCount,
          "requiredCount": ewma.rhrTrendReference.requiredSampleCount,
        ]
        result["currentHRVRecentEligibility"] = [
          "count": context.hrvTrend.ewma?.recentSampleCount ?? 0
        ]
        result["currentRHRRecentEligibility"] = [
          "count": context.restingHeartRateTrend.ewma?.recentSampleCount ?? 0
        ]
        result["fixedSleep"] = [
          "unit": ewma.sleepDeviationUnit,
          "historicalReferenceRequired": false,
        ]
      }
      return result
    }

    private static func statistics(_ results: [ReadinessV2Result]) -> [String: Any] {
      let values = results.compactMap(\.value)
      let display = results.compactMap(\.roundedValue)
      var clipping: [String: Int] = [:]
      var causes: [String: Int] = [:]
      for result in results {
        for component in result.components {
          if component.deviation.wasClipped { clipping[component.kind.rawValue, default: 0] += 1 }
          for subterm in component.subterms where subterm.deviation.wasClipped {
            clipping["\(component.kind.rawValue).\(subterm.kind.rawValue)", default: 0] += 1
          }
        }
        for issue in result.issues {
          causes["\(issue.metric?.rawValue ?? "score"):\(issue.reason.rawValue)", default: 0] += 1
        }
      }
      var result: [String: Any] = [
        "rawMinimum": optional(values.min()), "rawMaximum": optional(values.max()),
        "displayedMinimum": optional(display.min()), "displayedMaximum": optional(display.max()),
        "rawLowerBoundHits": values.filter { $0 <= 5 }.count,
        "rawUpperBoundHits": values.filter { $0 >= 95 }.count,
        "displayedLowerBoundHits": display.filter { $0 <= 5 }.count,
        "displayedUpperBoundHits": display.filter { $0 >= 95 }.count,
        "finalClampApplied": results.filter { ($0.finalClampAdjustment ?? 0) != 0 }.count,
        "componentClipping": clipping, "unavailableCauses": causes,
      ]
      for status in [ScoreStatus.available, .provisional, .unavailable] {
        result[status.rawValue] = results.filter { $0.status == status }.count
      }
      for band in [ScoreBand.lower, .middle, .upper] {
        result[band.rawValue] = results.filter { $0.band == band }.count
      }
      return result
    }

    private static func score(_ result: ReadinessV2Result) -> String {
      "\(number(result.value)) / \(number(result.roundedValue)) / \(result.band?.rawValue ?? "–") / \(result.status.rawValue)"
    }

    private static func optional(_ x: Double?) -> Any { x.map { $0 as Any } ?? NSNull() }
    private static func number(_ value: Double?) -> String {
      value.map { String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), $0) } ?? "–"
    }

    /// Reflect stored diagnostic fields without changing the frozen package types to Codable.
    /// Computed values are exported explicitly by the surrounding report.
    private static func evidence(_ value: Any) -> Any {
      if let date = value as? Date { return date.ISO8601Format() }
      if let id = value as? UUID { return id.uuidString }
      let mirror = Mirror(reflecting: value)
      if mirror.displayStyle == .optional {
        return mirror.children.first.map { evidence($0.value) } ?? NSNull()
      }
      if mirror.displayStyle == .collection || mirror.displayStyle == .set {
        return mirror.children.map { evidence($0.value) }
      }
      if mirror.displayStyle == .dictionary {
        var result: [String: Any] = [:]
        for entry in mirror.children {
          let parts = Array(Mirror(reflecting: entry.value).children)
          result[String(describing: parts[0].value)] = evidence(parts[1].value)
        }
        return result
      }
      if mirror.displayStyle == .enum { return String(describing: value) }
      if mirror.children.isEmpty {
        if let value = value as? String { return value }
        if let value = value as? Bool { return value }
        if let value = value as? Double { return value.isFinite ? value as Any : NSNull() }
        if let value = value as? Int { return value }
        return String(describing: value)
      }
      return Dictionary(
        uniqueKeysWithValues: mirror.children.map { ($0.label!, evidence($0.value)) })
    }
  }
#endif
