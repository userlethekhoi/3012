import SwiftUI

@main
struct ThreeZeroOneTwoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var downloads = BackgroundDownloadManager()
    @StateObject private var manualPatches = ManualPatchManager()
    @StateObject private var sessionLogger = SessionLogger()
    @StateObject private var deviceProfile = DeviceProfileService()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(downloads)
                .environmentObject(manualPatches)
                .environmentObject(sessionLogger)
                .environmentObject(deviceProfile)
        }
    }
}
