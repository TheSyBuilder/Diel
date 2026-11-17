import SwiftUI

struct ShellScreen: View {
  @Environment(\.dielTheme) private var theme
  let title: LocalizedStringKey

  var body: some View {
    NavigationStack {
      theme.colors.canvas
        .ignoresSafeArea()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
  }
}
