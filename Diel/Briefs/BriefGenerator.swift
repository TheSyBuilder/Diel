import Foundation
import FoundationModels
import ScoringKit
import Synchronization

nonisolated enum BriefSource: String, Codable, Sendable { case template, onDevice }

nonisolated struct Brief: Codable, Equatable, Sendable {
  var headline: String
  var body: String
  var source: BriefSource? = .template
}

@Generable
nonisolated private struct GeneratedBrief {
  @Guide(
    description: "A plain headline, at most eight words, with no exclamation mark or medical claim."
  )
  var headline: String
  @Guide(
    description:
      "At most two sentences, about 45 words. Only supplied facts; a gentle practical suggestion is allowed, no rating or Load numbers, diagnoses or exclamation marks."
  )
  var body: String
}

nonisolated protocol BriefGenerator: Sendable {
  func generate(_ input: BriefInput) async throws -> Brief
  /// Loads model resources ahead of the day's first generation. Templates need none.
  func prewarm() async
}

extension BriefGenerator {
  nonisolated func prewarm() async {}
}

nonisolated struct TemplateBriefGenerator: BriefGenerator {
  func generate(_ input: BriefInput) async -> Brief { Self.make(input) }

  static func make(_ input: BriefInput) -> Brief {
    let scoresUnavailable =
      input.readiness.value == nil && input.sleep.value == nil && input.missingLoad
    if scoresUnavailable && input.sleepDurationMinutes == nil && input.sleepNeedMinutes == nil {
      return Brief(
        headline: "Scores are unavailable today",
        body: input.learning
          ? "Readiness, Sleep and Load are unavailable; Diel is still learning your normal."
          : "Readiness, Sleep and Load are unavailable, so there are no scores to summarize.")
    }
    let headline: String
    if scoresUnavailable {
      headline = "Scores are unavailable today"
    } else if input.learning {
      headline = "Your usual pattern is taking shape"
    } else {
      switch input.readiness.band {
      case .upper: headline = "Readiness looks strong today"
      case .middle: headline = "A mixed Readiness picture"
      case .lower: headline = "Readiness looks low today"
      case nil: headline = "Today's available readings"
      }
    }
    var facts: [String] = scoresUnavailable ? ["Readiness, Sleep and Load are unavailable"] : []
    if let value = input.readiness.displayValue {
      facts.append("Readiness \(number(value)) reflects \(input.readiness.why)")
    }
    var sleep = input.sleep.displayValue.map { "Sleep \(number($0))" }
    if let duration = input.sleepDurationMinutes, let need = input.sleepNeedMinutes {
      let shortfall =
        input.sleepDifferenceMinutes.flatMap {
          $0 < 0 ? ", \(TodayPresentation.duration(minutes: -$0)) short" : nil
        } ?? ""
      sleep =
        "\(sleep.map { "\($0) followed " } ?? "Sleep was ")\(TodayPresentation.duration(minutes: duration)) against \(TodayPresentation.duration(minutes: need)) needed\(shortfall)"
    } else if let duration = input.sleepDurationMinutes {
      sleep =
        "\(sleep.map { "\($0) followed " } ?? "Sleep was ")\(TodayPresentation.duration(minutes: duration))"
    } else if let need = input.sleepNeedMinutes {
      sleep =
        "\(sleep.map { "\($0); " } ?? "")sleep need was \(TodayPresentation.duration(minutes: need))"
    }
    if let sleep { facts.append(sleep) }
    if !input.missingLoad {
      // Load is qualitative only, so the brief stays stable while the running number moves.
      let timing = input.loadComparisonIsSameTime ? " by this time" : " across a full day"
      switch input.loadComparison {
      // A missing state always arrives with missingLoad, so this branch is never reached by it.
      case .missing: break
      case .none: facts.append("load shows no training yet")
      case .lighter: facts.append("load is light so far, below usual\(timing)")
      case .usual: facts.append("load is near usual so far\(timing)")
      case .heavier: facts.append("load is heavier than usual so far\(timing)")
      case .unknown: facts.append("load is light so far")
      }
    }
    let unavailableScoreLabels = [
      "Readiness unavailable", "Sleep score unavailable", "Load unavailable",
    ]
    var notes = (input.evidenceLimitations ?? []).filter {
      !scoresUnavailable || !unavailableScoreLabels.contains($0)
    }
    if notes.isEmpty && input.hasMissingData && !scoresUnavailable {
      notes.append("Some readings missing or partial")
    }
    if input.learning { notes.insert("Still learning your normal", at: 0) }
    // Keep the limitation short enough that the measured evidence remains the main sentence.
    notes = Array(notes.prefix(2))
    let suggestion: String?
    if let difference = input.sleepDifferenceMinutes, difference < 0 {
      suggestion = "An easier start leaves room to reassess after short sleep"
    } else if input.readiness.band == .lower {
      suggestion = "A gentler start leaves room to reassess as the day unfolds"
    } else {
      suggestion = nil
    }
    switch input.disagreement {
    case .feelingLower: notes.append("at check-in, you felt lower than Readiness suggested")
    case .feelingHigher: notes.append("at check-in, you felt better than Readiness suggested")
    case .none: if input.skipped { notes.append("you skipped the check-in") }
    }
    let evidence = facts.joined(separator: "; ") + "."
    if let suggestion,
      BriefValidator.words(evidence + " " + (notes + [suggestion]).joined(separator: "; ")) <= 60
    {
      notes.insert(suggestion, at: max(0, notes.count - (input.disagreement == .none ? 0 : 1)))
    }
    return Brief(
      headline: headline,
      body: notes.isEmpty ? evidence : "\(evidence) \(notes.joined(separator: "; ")).")
  }

  private static func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
  }

}

nonisolated protocol BriefLanguageModel: Sendable {
  func isAvailable() -> Bool
  func makeSession() -> any BriefLanguageModelSession
}

nonisolated protocol BriefLanguageModelSession: Sendable {
  func prewarm() async throws
  func respond(to values: String) async throws -> Brief
}

/// This implementation is compiled on simulator, but the factory never selects it there or in tests.
nonisolated struct FoundationModelsBriefGenerator: BriefGenerator {
  private let model: any BriefLanguageModel
  private let warm = WarmBriefSession()

  init(model: any BriefLanguageModel = SystemBriefLanguageModel()) { self.model = model }

  /// Creates and prewarms one session for the next generation. A generation that starts while
  /// this is still running takes the same session; the model serialises its own work.
  @concurrent
  func prewarm() async {
    guard !warm.isOccupied, model.isAvailable() else { return }
    let session = model.makeSession()
    guard warm.offer(session) else { return }
    try? await session.prewarm()
  }

  // Swift 6 caller-executor inheritance must never put model work on the UI executor.
  @concurrent
  func generate(_ input: BriefInput) async -> Brief {
    let fallback = TemplateBriefGenerator.make(input)
    guard model.isAvailable() else { return fallback }
    do {
      try Task.checkCancellation()
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let values = String(decoding: try encoder.encode(input), as: UTF8.self)
      let session = warm.take() ?? model.makeSession()
      try Task.checkCancellation()
      let candidate = try await session.respond(to: values)
      guard BriefValidator.isValid(candidate, for: input) else { return fallback }
      return Brief(headline: candidate.headline, body: candidate.body, source: .onDevice)
    } catch { return fallback }
  }
}

/// Holds at most one prewarmed session until the next generation takes it.
nonisolated private final class WarmBriefSession: Sendable {
  private let session = Mutex<(any BriefLanguageModelSession)?>(nil)

  var isOccupied: Bool { session.withLock { $0 != nil } }

  func offer(_ candidate: any BriefLanguageModelSession) -> Bool {
    session.withLock { stored in
      guard stored == nil else { return false }
      stored = candidate
      return true
    }
  }

  func take() -> (any BriefLanguageModelSession)? { session.withLock { $0.take() } }
}

nonisolated private struct SystemBriefLanguageModel: BriefLanguageModel {
  func isAvailable() -> Bool { SystemLanguageModel.default.availability == .available }
  func makeSession() -> any BriefLanguageModelSession { SystemBriefSession() }
}

/// The SDK's nonsending respond call inherits this worker actor, never MainActor.
private actor SystemBriefSession: BriefLanguageModelSession {
  private let session: LanguageModelSession

  init() {
    precondition(!Thread.isMainThread)
    session = LanguageModelSession(
      model: SystemLanguageModel.default,
      instructions: """
        Write a personal daily reflection from only the supplied computed values.
        Use a headline of at most eight words and a body of at most two sentences, around 45 words.
        Use plain, specific English. No exclamation marks, medical claims, diagnoses, imperative instructions or filler.
        A gentle conservative suggestion grounded in the supplied sleep or Readiness is allowed.
        Do not display engineering/provenance wording: EWMA, half-life, reference, series points,
        readings needed, native units, complete collection, source dates/IDs, bundled or Diel estimate.
        If all scores are missing, say they are unavailable; do not imply any available score exists.
        Summarize available Readiness, Sleep and Load scores and their drivers even when another input is missing.
        Include the supplied sleep duration, need and shortfall when available.
        A provisional Readiness or Sleep score means partial evidence, not an absent score.
        Name the supplied evidenceLimitations briefly after the known facts; do not replace those facts with a generic partial picture.
        A learning normal limits context but does not erase available measurements.
        Use time-neutral language. Never say morning or this morning, since the brief can be read after noon.
        Load is a running all-day measure; describe it only through loadComparison and never state a Load number.
        loadComparison missing means Load is unavailable, none means no training yet, lighter means light so far, usual means near usual so far,
        heavier means heavier than usual so far, and unknown means light so far with no usual to compare.
        When missingLoad is true, Load is unavailable rather than no training. Never infer a rest day.
        Partial running Load alone does not make the picture limited.
        The usual is a prior-28-day median. loadComparisonIsSameTime means compare by this time, otherwise say across a full day.
        Format durations of at least 60 minutes as hours and minutes, for example 2h 15m.
        Never infer missing measurements. Never introduce a number not present in the input.
        Do not repeat the rating number. Ratings 1 and 2 mean lower, 3 means middle, 4 and 5 mean upper.
        When that category differs from the Readiness band, kindly acknowledge the difference.
        Otherwise make no claim that their feeling agrees with the score. Load has no health grade.
        Resting HR comparisons are Garmin daily resting heart rate, never verified overnight or nighttime RHR.
        Do not relabel daily resting heart rate as an overnight measurement.
        """
    )
  }

  func prewarm() { session.prewarm() }

  func respond(to values: String) async throws -> Brief {
    let result = try await session.respond(
      to: values, generating: GeneratedBrief.self,
      options: GenerationOptions(), contextOptions: ContextOptions()
    ).content
    return Brief(headline: result.headline, body: result.body, source: .onDevice)
  }
}

nonisolated enum BriefGeneratorFactory {
  static func make(offline: Bool) -> any BriefGenerator {
    #if targetEnvironment(simulator)
      return TemplateBriefGenerator()
    #else
      return offline ? TemplateBriefGenerator() : FoundationModelsBriefGenerator()
    #endif
  }
}

/// A detached race deliberately does not use a task group: a cancelled model may never return.
nonisolated enum BriefGenerationDeadline {
  @concurrent
  static func generate(
    _ input: BriefInput, using generator: any BriefGenerator, timeout: Duration = .seconds(10)
  ) async -> Brief {
    let fallback = TemplateBriefGenerator.make(input)
    let race = BriefResultRace<Brief>()
    let deadline = ContinuousClock.now.advanced(by: timeout)
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        race.install(continuation)
        race.add(
          Task.detached {
            guard !Task.isCancelled else { return }
            let candidate = (try? await generator.generate(input)) ?? fallback
            race.resolve(BriefValidator.isValid(candidate, for: input) ? candidate : fallback)
          })
        race.add(
          Task.detached {
            do {
              try await Task.sleep(until: deadline, clock: .continuous)
              race.resolve(fallback)
            } catch {}
          })
      } ?? fallback
    } onCancel: {
      race.resolve(nil)
    }
  }

  /// Cancelling a view's waiter must not cancel a shared, durably reserved daily generation.
  @concurrent
  static func wait<Value: Sendable>(for job: Task<Value, Never>) async -> Value? {
    let race = BriefResultRace<Value>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        race.install(continuation)
        race.add(Task.detached { race.resolve(await job.value) })
      }
    } onCancel: {
      race.resolve(nil)
    }
  }
}

nonisolated private final class BriefResultRace<Value: Sendable>: Sendable {
  private struct State {
    var finished = false
    var result: Value?
    var continuation: CheckedContinuation<Value?, Never>?
    var tasks: [Task<Void, Never>] = []
  }
  private let state = Mutex(State())

  func install(_ continuation: CheckedContinuation<Value?, Never>) {
    let completed = state.withLock { state -> (Bool, Value?) in
      if state.finished { return (true, state.result) }
      state.continuation = continuation
      return (false, nil)
    }
    if completed.0 { continuation.resume(returning: completed.1) }
  }

  func add(_ task: Task<Void, Never>) {
    let finished = state.withLock { state in
      if state.finished { return true }
      state.tasks.append(task)
      return false
    }
    if finished { task.cancel() }
  }

  func resolve(_ result: Value?) {
    let completion = state.withLock {
      state -> (CheckedContinuation<Value?, Never>?, [Task<Void, Never>]) in
      guard !state.finished else { return (nil, []) }
      state.finished = true
      state.result = result
      let completion = (state.continuation, state.tasks)
      state.continuation = nil
      state.tasks = []
      return completion
    }
    for task in completion.1 { task.cancel() }
    completion.0?.resume(returning: result)
  }
}
