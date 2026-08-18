import UIKit

final class BackgroundSessionEvents {
    static let shared = BackgroundSessionEvents()
    private var completionHandler: (() -> Void)?

    private init() {}

    func register(_ completionHandler: @escaping () -> Void) {
        self.completionHandler = completionHandler
    }

    func finish() {
        completionHandler?()
        completionHandler = nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackgroundSessionEvents.shared.register(completionHandler)
    }
}
