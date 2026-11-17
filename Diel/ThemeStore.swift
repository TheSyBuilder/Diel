import Foundation
import Observation
import UIKit

@MainActor
protocol ThemeIconClient {
  var supportsAlternateIcons: Bool { get }
  var alternateIconName: String? { get }
  func setAlternateIconName(_ name: String?) async throws
}

@MainActor
private struct ApplicationThemeIconClient: ThemeIconClient {
  var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
  var alternateIconName: String? { UIApplication.shared.alternateIconName }

  func setAlternateIconName(_ name: String?) async throws {
    try await UIApplication.shared.setAlternateIconName(name)
  }
}

@Observable
@MainActor
final class ThemeStore {
  static let persistenceKey = "diel.appearance.theme"

  private(set) var selectedTheme: DielTheme
  private(set) var iconError: LocalizedStringResource?
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let iconClient: (any ThemeIconClient)?
  @ObservationIgnored private var iconTask: Task<Void, Never>?

  init(defaults: UserDefaults = .standard, iconClient: (any ThemeIconClient)? = nil) {
    self.defaults = defaults
    selectedTheme =
      defaults.string(forKey: Self.persistenceKey).flatMap(DielTheme.init(rawValue:))
      ?? .ember
    if let iconClient {
      self.iconClient = iconClient
    } else {
      #if DEBUG
        self.iconClient = AppDependencies.isUnitTestHost ? nil : ApplicationThemeIconClient()
      #else
        self.iconClient = ApplicationThemeIconClient()
      #endif
    }
  }

  func select(_ theme: DielTheme) {
    selectedTheme = theme
    defaults.set(theme.rawValue, forKey: Self.persistenceKey)
    iconError = nil
    Task { await synchronizeIcon() }
  }

  func retryIconChange() {
    iconError = nil
    Task { await synchronizeIcon() }
  }

  /// One icon request runs at a time, and each completion checks the latest theme selection.
  func synchronizeIcon() async {
    if let iconTask {
      await iconTask.value
      return
    }
    guard iconClient != nil else { return }
    let task = Task { await applyLatestIcon() }
    iconTask = task
    await task.value
  }

  private func applyLatestIcon() async {
    defer { iconTask = nil }
    guard let iconClient else { return }
    while true {
      let requestedTheme = selectedTheme
      let requestedIcon = requestedTheme.alternateIconName
      if iconClient.alternateIconName == requestedIcon {
        iconError = nil
        return
      }
      guard iconClient.supportsAlternateIcons else {
        iconError = "The app icon could not be changed. Try again."
        return
      }
      do {
        try await iconClient.setAlternateIconName(requestedIcon)
      } catch {
        if selectedTheme != requestedTheme { continue }
        iconError = "The app icon could not be changed. Try again."
        return
      }
      guard selectedTheme == requestedTheme else { continue }
      iconError = nil
      return
    }
  }
}
