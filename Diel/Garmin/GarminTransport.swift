import Foundation

nonisolated enum GarminOrigin {
  static let url = URL(string: "https://personal.connectapi.garmin.com")!

  static func permits(_ url: URL?) -> Bool {
    guard let url else { return false }
    return url.scheme?.lowercased() == "https"
      && url.host?.lowercased() == Self.url.host
      && (url.port == nil || url.port == 443)
      && url.user == nil && url.password == nil
  }
}

nonisolated struct GarminHTTPResponse: Sendable {
  let data: Data
  let status: Int
  let retryAfter: String?

  init(data: Data, status: Int, retryAfter: String? = nil) {
    self.data = data
    self.status = status
    self.retryAfter = retryAfter
  }
}

nonisolated protocol GarminTransport: Sendable {
  func send(_ request: URLRequest) async throws -> GarminHTTPResponse
}

/// Ephemeral configuration has no disk cache, cookies, or stored HTTP credentials.
nonisolated final class URLSessionGarminTransport: GarminTransport, Sendable {
  private let session: URLSession

  init() {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpCookieStorage = nil
    configuration.httpShouldSetCookies = false
    configuration.urlCredentialStorage = nil
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 30
    session = URLSession(
      configuration: configuration, delegate: OriginDelegate(), delegateQueue: nil)
  }

  func send(_ request: URLRequest) async throws -> GarminHTTPResponse {
    guard GarminOrigin.permits(request.url) else { throw GarminError.invalidEndpoint }
    do {
      let (data, response) = try await session.data(for: request)
      try Task.checkCancellation()
      guard let response = response as? HTTPURLResponse, GarminOrigin.permits(response.url) else {
        throw GarminError.transport
      }
      return GarminHTTPResponse(
        data: data, status: response.statusCode,
        retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch let error as GarminError {
      throw error
    } catch {
      throw GarminError.transport
    }
  }

  private final class OriginDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    nonisolated func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
      completionHandler(GarminOrigin.permits(request.url) ? request : nil)
    }
  }
}
