import Foundation

nonisolated struct GarminTiming: Sendable {
  let now: @Sendable () -> Date
  let sleep: @Sendable (TimeInterval) async throws -> Void
  let waitUntil: @Sendable (Date) async throws -> Void

  init(
    now: @escaping @Sendable () -> Date,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
    waitUntil: (@Sendable (Date) async throws -> Void)? = nil
  ) {
    self.now = now
    self.sleep = sleep
    self.waitUntil =
      waitUntil ?? { date in
        let delay = date.timeIntervalSince(now())
        if delay > 0 { try await sleep(delay) }
      }
  }

  static let continuous = GarminTiming(
    now: { Date() },
    sleep: { seconds in try await Task.sleep(for: .seconds(seconds)) })
}

/// One instance must be shared by token exchange and all data requests.
actor GarminRequestScheduler {
  private struct Waiter {
    let id: UUID
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let transport: any GarminTransport
  private let timing: GarminTiming
  private let log: any DielEventLogging
  private var busy = false
  private var waiters: [Waiter] = []
  private var lastSend: Date?
  private var cooldown: Date?

  init(
    transport: any GarminTransport = URLSessionGarminTransport(),
    timing: GarminTiming = .continuous, log: any DielEventLogging = DielLog()
  ) {
    self.transport = transport
    self.timing = timing
    self.log = log
  }

  /// Deadline covers queueing, pacing and retry waits; a server cooldown survives this call.
  func send(
    _ request: URLRequest, operation: DielEvent.Operation, deadline: Date
  ) async throws -> GarminHTTPResponse {
    try await acquire(deadline: deadline)
    defer { release() }
    var lastStatus: Int?
    do {
      for attempt in 0...3 {
        try Task.checkCancellation()
        let now = timing.now()
        let earliest = max(lastSend?.addingTimeInterval(0.3) ?? now, cooldown ?? now)
        try await wait(until: earliest, deadline: deadline)
        guard timing.now() < deadline else {
          throw GarminError.retryAfter(max(earliest, timing.now()))
        }
        lastSend = timing.now()
        log.record(.requestStarted(operation))
        var boundedRequest = request
        boundedRequest.timeoutInterval = min(
          request.timeoutInterval, deadline.timeIntervalSince(timing.now()))
        let sentAt = timing.now()
        let response = try await transport.send(boundedRequest)
        let roundTrip = timing.now().timeIntervalSince(sentAt)
        log.record(.requestTiming(operation, milliseconds: Int((roundTrip * 1000).rounded())))
        try Task.checkCancellation()
        lastStatus = response.status
        log.record(.response(operation, status: response.status))
        guard response.status == 429 || (500...599).contains(response.status) else {
          return response
        }
        let base = timing.now().addingTimeInterval(pow(2, Double(min(attempt, 2))))
        let retry = max(base, retryDate(response.retryAfter) ?? base)
        cooldown = max(cooldown ?? retry, retry)
        guard attempt < 3 else { throw GarminError.retryAfter(retry) }
        guard retry < deadline else { throw GarminError.retryAfter(retry) }
        log.record(.retry(operation, attempt: attempt + 1))
      }
      throw GarminError.transport
    } catch GarminError.retryAfter(let date) {
      if let lastStatus { throw GarminError.retryExhausted(date, status: lastStatus) }
      throw GarminError.retryAfter(date)
    }
  }

  private func wait(until date: Date, deadline: Date) async throws {
    guard date < deadline else { throw GarminError.retryAfter(date) }
    let delay = date.timeIntervalSince(timing.now())
    if delay > 0 { try await timing.sleep(delay) }
    try Task.checkCancellation()
  }

  private func retryDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }),
      let delta = Double(text), delta.isFinite
    {
      return timing.now().addingTimeInterval(delta)
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    for format in [
      "EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy",
    ] {
      formatter.dateFormat = format
      if let date = formatter.date(from: text) { return date }
    }
    return nil
  }

  private func acquire(deadline: Date) async throws {
    try Task.checkCancellation()
    guard timing.now() < deadline else { throw GarminError.retryAfter(timing.now()) }
    if !busy {
      busy = true
      return
    }
    let id = UUID()
    let timeout = Task {
      do {
        try await timing.waitUntil(deadline)
        expireWaiter(id)
      } catch {
        // Cancellation only ends this queue timer.
      }
    }
    defer { timeout.cancel() }
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        waiters.append(Waiter(id: id, continuation: continuation))
      }
      // A cancellation after release acquired the slot: pass it on before throwing.
      if Task.isCancelled {
        release()
        throw CancellationError()
      }
    } onCancel: {
      Task { await self.cancelWaiter(id) }
    }
  }

  private func expireWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: GarminError.retryAfter(timing.now()))
  }

  private func cancelWaiter(_ id: UUID) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func release() {
    if waiters.isEmpty {
      busy = false
    } else {
      waiters.removeFirst().continuation.resume()
    }
  }
}
