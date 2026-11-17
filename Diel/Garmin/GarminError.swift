import Foundation

/// Contains no server text, URLs, request values, or underlying raw errors.
nonisolated enum GarminError: Error, Equatable {
  case noCredential
  case credentialChanged
  case invalidCredential
  case invalidTokenResponse
  case invalidEndpoint
  case unauthorized
  case httpStatus(Int)
  case transport
  case decoding(GarminPayload.Family)
  case retryAfter(Date)
  case retryExhausted(Date, status: Int)
}
