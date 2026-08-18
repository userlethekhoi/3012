import SwiftUI

@main
struct ThreeZeroOneTwoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var downloads = BackgroundDownloadManager()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(downloads)
        }
    }
}
