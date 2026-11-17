import Foundation
import Observation

@Observable
@MainActor
final class SettingsModel {
  var entry = ""
  private(set) var isSaving = false
  private(set) var isRemovalRequested = false
  private(set) var errorMessage: LocalizedStringResource?
  let credentialsEnabled: Bool
  let sync: SyncCoordinator?
  private let credentials: any CredentialStore
  private let log: any DielEventLogging

  init(
    credentials: any CredentialStore, sync: SyncCoordinator?, credentialsEnabled: Bool = true,
    log: any DielEventLogging = DielLog()
  ) {
    self.credentials = credentials
    self.sync = sync
    self.credentialsEnabled = credentialsEnabled
    self.log = log
  }

  func clearEntry() {
    entry = ""
    cancelRemoval()
  }

  @discardableResult
  func requestRemoval() -> Bool {
    guard credentialsEnabled, !isSaving, !isRemovalRequested, sync?.hasSavedKey == true else {
      return false
    }
    isRemovalRequested = true
    return true
  }

  func cancelRemoval() { isRemovalRequested = false }

  func save() async {
    guard credentialsEnabled, !isSaving, let sync else {
      clearEntry()
      return
    }
    let value = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    clearEntry()
    guard !value.isEmpty else { return }
    isSaving = true
    errorMessage = nil
    defer { isSaving = false }
    await sync.prepareForCredentialChange()
    do {
      let revision = try await credentials.save(Data(value.utf8))
      try await sync.selectCredential(revision)
      log.record(.settingsSaved)
      sync.requestSync()
    } catch {
      errorMessage = "The key could not be saved. Try again."
      log.record(.settingsFailed)
    }
  }

  @discardableResult
  func confirmRemoval() -> Task<Void, Never>? {
    guard isRemovalRequested else { return nil }
    clearEntry()
    guard credentialsEnabled, !isSaving, let sync, sync.hasSavedKey else { return nil }
    isSaving = true
    errorMessage = nil
    return Task { await removeConfirmedCredential(sync: sync) }
  }

  private func removeConfirmedCredential(sync: SyncCoordinator) async {
    defer { isSaving = false }
    await sync.prepareForCredentialChange()
    do {
      try await credentials.remove()
      try await sync.selectCredential(nil)
      log.record(.settingsRemoved)
    } catch {
      errorMessage = "The key could not be removed. Try again."
      log.record(.settingsFailed)
    }
  }
}
