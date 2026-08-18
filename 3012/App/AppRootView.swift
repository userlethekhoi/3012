import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: AppTab = .store
    @AppStorage("appearance.mode") private var appearanceMode = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            StoreView()
                .tag(AppTab.store)
                .tabItem { Label("Kho", systemImage: "square.grid.2x2.fill") }

            InstalledView()
                .tag(AppTab.installed)
                .tabItem { Label("Đã cài", systemImage: "checkmark.seal.fill") }

            DownloadsView()
                .tag(AppTab.downloads)
                .tabItem { Label("Tải xuống", systemImage: "arrow.down.circle.fill") }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label("Cài đặt", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(preferredColorScheme)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

private enum AppTab: Hashable {
    case store
    case installed
    case downloads
    case settings
}
