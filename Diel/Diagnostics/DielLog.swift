import Foundation
import os

/// Only closed, reviewed metadata can enter diagnostics. Never add raw value/error overloads.
nonisolated enum DielEvent: Sendable, Equatable {
  enum Operation: Sendable, Equatable {
    case token
    case data(GarminPayload.Family)
  }
  case requestStarted(Operation)
  case response(Operation, status: Int)
  case requestTiming(Operation, milliseconds: Int)
  case retry(Operation, attempt: Int)
  case credentialChanged
  case syncStarted, syncCompleted, syncFailed
  case failure(SyncFailure)
  case rejectedRecord(date: DateKey?, fieldPath: String)
  #if DEBUG
    /// Field names only, never values, of a member rejected for a missing date.
    case rejectedRecordFields(memberIndex: Int, fields: [String])
  #endif
  case settingsSaved, settingsRemoved, settingsFailed
}

nonisolated protocol DielEventLogging: Sendable {
  func record(_ event: DielEvent)
}

nonisolated struct DielLog: DielEventLogging {
  private let logger = Logger(subsystem: "app.diel", category: "data")

  func record(_ event: DielEvent) {
    switch event {
    case .requestStarted(let operation):
      logger.debug("Request started operation=\(code(operation), privacy: .private)")
    case .response(let operation, let status):
      logger.debug(
        "Response operation=\(code(operation), privacy: .private) status=\(status, privacy: .private)"
      )
    case .requestTiming(let operation, let milliseconds):
      logger.debug(
        "Request timing operation=\(code(operation), privacy: .private) ms=\(milliseconds, privacy: .private)"
      )
    case .retry(let operation, let attempt):
      logger.debug(
        "Retry operation=\(code(operation), privacy: .private) attempt=\(attempt, privacy: .private)"
      )
    case .credentialChanged: logger.info("Credential revision changed")
    case .syncStarted: logger.info("Sync started")
    case .syncCompleted: logger.info("Sync completed")
    case .syncFailed: logger.error("Sync failed")
    case .failure(let failure):
      logger.error(
        "Sync failure step=\(failure.step.code, privacy: .public) phase=\(failure.stage.rawValue, privacy: .public) status=\(failure.httpStatus.map(String.init) ?? "none", privacy: .public) reason=\(failure.reason.rawValue, privacy: .public)"
      )
    case .rejectedRecord(let date, let fieldPath):
      logger.error(
        "Rejected record date=\(date?.rawValue ?? "unknown", privacy: .private) field=\(fieldPath, privacy: .private)"
      )
    #if DEBUG
      case .rejectedRecordFields(let memberIndex, let fields):
        logger.error(
          "Rejected record fields member=\(memberIndex, privacy: .private) fields=\(fields.joined(separator: ","), privacy: .private)"
        )
    #endif
    case .settingsSaved: logger.info("Credential saved")
    case .settingsRemoved: logger.info("Credential removed")
    case .settingsFailed: logger.error("Credential operation failed")
    }
  }

  private func code(_ operation: DielEvent.Operation) -> String {
    switch operation {
    case .token: "token"
    case .data(let family): family.rawValue
    }
  }
}
