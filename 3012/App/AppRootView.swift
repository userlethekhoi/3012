import SwiftUI

struct AppRootView: View {
    @State private var selectedTab: AppTab = .home
    @AppStorage("appearance.mode") private var appearanceMode = "system"
    @AppStorage("appearance.interfaceScale") private var interfaceScaleRawValue = AppInterfaceScale.standard.rawValue
    @AppStorage("app.language") private var appLanguage = "system"

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(AppTab.home)
                .tabItem { Label("Home", systemImage: "house.fill") }

            FilesView()
                .tag(AppTab.files)
                .tabItem { Label("Files", systemImage: "folder.fill") }

            PatchesView()
                .tag(AppTab.patches)
                .tabItem { Label("Patches", systemImage: "shippingbox.fill") }

            SettingsView()
                .tag(AppTab.settings)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(AppTheme.accent)
        .preferredColorScheme(preferredColorScheme)
        .dynamicTypeSize(interfaceScale.dynamicTypeSize)
        .environment(\.locale, selectedLocale)
        .id(appLanguage)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var selectedLocale: Locale {
        appLanguage == "system" ? .autoupdatingCurrent : Locale(identifier: appLanguage)
    }

    private var interfaceScale: AppInterfaceScale {
        AppInterfaceScale(rawValue: interfaceScaleRawValue) ?? .standard
    }
}

private enum AppTab: Hashable {
    case home
    case files
    case patches
    case settings
}
