//
//  DielApp.swift
//  Diel
//
//  Created by Taleb Alhajji on 05/11/2026.
//

import SwiftUI

@main
struct DielApp: App {
  @UIApplicationDelegateAdaptor(DielApplicationDelegate.self) private var appDelegate
  @Environment(\.scenePhase) private var scenePhase
  @State private var dependencies = DielApplicationDelegate.dependencies
  @State private var themeStore = ThemeStore()
  var body: some Scene {
    WindowGroup {
      ContentView(dependencies: dependencies)
        .environment(themeStore)
        .task {
          await dependencies.start()
          await dependencies.sceneChanged(
            active: scenePhase == .active, background: scenePhase == .background)
        }
        .task { await themeStore.synchronizeIcon() }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in
          Task {
            await dependencies.sceneChanged(
              active: phase == .active, background: phase == .background)
          }
        }
    }
  }
}
