import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

public enum WorkspaceDocumentPickerMode: String, Identifiable, Sendable {
    case singleFile
    case folder
    case folderFilesCopy
    case zip
    case themeJSON

    public var id: String { rawValue }
}

public struct PickedDocumentResource: Sendable {
    public let url: URL
    public let hasSecurityScope: Bool
    public let isTemporaryCopy: Bool

    public init(url: URL, hasSecurityScope: Bool, isTemporaryCopy: Bool) {
        self.url = url
        self.hasSecurityScope = hasSecurityScope
        self.isTemporaryCopy = isTemporaryCopy
    }
}

/// Native UIKit presenter that avoids SwiftUI `.sheet` / `UIMenu` / `CommandPaletteSheet` dismissal collisions
/// when opening system Files/Folders (`UIDocumentPickerViewController`), Photo Library (`PHPickerViewController`),
/// or Camera (`UIImagePickerController`), while capturing security-scoped URL access synchronously in the delegate callback.
@MainActor
public final class NativeDocumentPickerPresenter: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIAdaptivePresentationControllerDelegate {
    public static let shared = NativeDocumentPickerPresenter()

    private var activePickSingle: ((URL) -> Void)?
    private var activePickMultiple: (([URL]) -> Void)?
    private var activePickResources: (([PickedDocumentResource]) -> Void)?
    private var activePickIsCopy: Bool = true
    private var activePickImages: (([UIImage]) -> Void)?
    private var activePickCameraImage: ((UIImage) -> Void)?
    private var activePresentedController: UIViewController?

    private override init() {
        super.init()
    }

    // MARK: - Top-Most Presenter Discovery & Menu-Safe Presentation
    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let normalWindows = activeScene?.windows.filter { $0.windowLevel == .normal && !$0.isHidden } ?? []
        return normalWindows.first(where: { $0.isKeyWindow })
            ?? normalWindows.first
            ?? activeScene?.windows.first(where: { $0.isKeyWindow })
            ?? activeScene?.windows.first
    }

    private func topMostPresenter() -> UIViewController? {
        guard var top = keyWindow()?.rootViewController else { return nil }
        while let presented = top.presentedViewController {
            let className = String(describing: type(of: presented))
            if presented.isBeingDismissed
                || presented.isBeingPresented
                || className.contains("ContextMenu")
                || className.contains("_UIAlertControllerTextFieldViewController") {
                break
            }
            top = presented
        }
        return top
    }

    private func isTransientTransitionController(_ vc: UIViewController) -> Bool {
        let className = String(describing: type(of: vc))
        return vc.isBeingDismissed
            || vc.isBeingPresented
            || vc.presentedViewController != nil
            || className.contains("ContextMenu")
            || className.contains("PopoverPresentation")
    }

    private func presentWhenReady(_ viewController: UIViewController, retries: Int = 16) {
        guard !viewController.isBeingPresented, viewController.presentingViewController == nil else {
            return
        }
        if let top = topMostPresenter() {
            if isTransientTransitionController(top) {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] () -> Void in
                        self?.presentWhenReady(viewController, retries: retries - 1)
                    }
                    return
                }
            }
            top.present(viewController, animated: true)
            return
        }

        if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) { [weak self] () -> Void in
                self?.presentWhenReady(viewController, retries: retries - 1)
            }
        }
    }

    private func presentAlertWhenReady(
        _ alert: UIAlertController,
        retries: Int = 24,
        onAborted: (() -> Void)? = nil
    ) {
        guard !alert.isBeingPresented, alert.presentingViewController == nil else {
            return
        }
        if let top = topMostPresenter(), !isTransientTransitionController(top) {
            if let pop = alert.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            top.present(alert, animated: true)
            return
        }

        if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] () -> Void in
                self?.presentAlertWhenReady(alert, retries: retries - 1, onAborted: onAborted)
            }
        } else {
            onAborted?()
        }
    }

    @MainActor
    public func presentShareSheet(for url: URL) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] () -> Void in
            guard let self, let top = self.topMostPresenter() else { return }
            if let pop = activity.popoverPresentationController {
                pop.sourceView = top.view
                pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
                pop.permittedArrowDirections = []
            }
            if self.isTransientTransitionController(top) {
                self.presentWhenReady(activity, retries: 20)
            } else {
                top.present(activity, animated: true)
            }
        }
    }

    // MARK: - System Files / Folders / Archives Picker
    public func presentPicker(
        mode: WorkspaceDocumentPickerMode,
        initialDelay: TimeInterval = 0.08,
        onPickURL: @escaping (URL) -> Void,
        onPickURLs: (([URL]) -> Void)? = nil
    ) {
        presentResourcePicker(mode: mode, initialDelay: initialDelay) { resources in
            guard !resources.isEmpty else { return }
            if let onPickURLs {
                onPickURLs(resources.map(\.url))
            } else {
                for res in resources {
                    onPickURL(res.url)
                }
            }
        }
    }

    public func presentCustomFilePicker(
        allowedExtensions: [String],
        initialDelay: TimeInterval = 0.08,
        onPickURL: @escaping (URL) -> Void
    ) {
        activePickMultiple = nil
        activePickResources = nil
        activePickSingle = onPickURL

        var resolvedTypes: [UTType] = []
        for rawExt in allowedExtensions {
            let clean = rawExt.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased()
            guard !clean.isEmpty else { continue }
            if let ut = UTType(filenameExtension: clean), !resolvedTypes.contains(ut) {
                resolvedTypes.append(ut)
            }
            if clean == "zip" || clean == "ipa" {
                if !resolvedTypes.contains(.archive) { resolvedTypes.append(.archive) }
            }
        }
        // Include `.data` / `.item` so unregistered binary extensions such as `.ipa` or `.dylib` remain selectable on iOS 15+.
        for fallback in [UTType.data, UTType.item] where !resolvedTypes.contains(fallback) {
            resolvedTypes.append(fallback)
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: resolvedTypes, asCopy: true)
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        picker.presentationController?.delegate = self
        activePickIsCopy = true
        activePresentedController = picker

        let launch: () -> Void = { [weak self] () -> Void in
            self?.presentWhenReady(picker)
        }
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: launch)
        } else {
            launch()
        }
    }

    public func presentResourcePicker(
        mode: WorkspaceDocumentPickerMode,
        initialDelay: TimeInterval = 0.08,
        onPickResources: @escaping ([PickedDocumentResource]) -> Void
    ) {
        activePickSingle = nil
        activePickMultiple = nil
        activePickResources = onPickResources

        let picker: UIDocumentPickerViewController
        let isCopyMode: Bool
        switch mode {
        case .folder:
            // Important on iOS 15-26: use the convenience initializer without `asCopy:` for `.folder`
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false
            isCopyMode = false
        case .singleFile:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .data, .content, .text, .sourceCode],
                asCopy: false
            )
            picker.allowsMultipleSelection = true
            isCopyMode = false
        case .folderFilesCopy:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .data, .content, .text, .sourceCode],
                asCopy: true
            )
            picker.allowsMultipleSelection = true
            isCopyMode = true
        case .zip:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.zip, .archive, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
            isCopyMode = true
        case .themeJSON:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.json, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
            isCopyMode = true
        }
        activePickIsCopy = isCopyMode
        picker.shouldShowFileExtensions = true
        picker.delegate = self
        picker.presentationController?.delegate = self
        activePresentedController = picker

        let launch: () -> Void = { [weak self] () -> Void in
            self?.presentWhenReady(picker)
        }
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay, execute: launch)
        } else {
            launch()
        }
    }

    public nonisolated func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        // Synchronously acquire security-scoped access before returning control to FileProvider
        var scopedEntries: [(url: URL, acquired: Bool)] = []
        for url in urls {
            let acquired = url.startAccessingSecurityScopedResource()
            scopedEntries.append((url, acquired))
        }
        Task { @MainActor [weak self] () -> Void in
            guard let self else {
                for entry in scopedEntries where entry.acquired {
                    entry.url.stopAccessingSecurityScopedResource()
                }
                return
            }
            let isCopy = self.activePickIsCopy
            let resourcesCallback = self.activePickResources
            let single = self.activePickSingle
            let multi = self.activePickMultiple
            self.activePickResources = nil
            self.activePickSingle = nil
            self.activePickMultiple = nil
            self.activePresentedController = nil

            if isCopy {
                // In asCopy mode the URLs point to temporary inbox copies; release temporary FileProvider scopes safely.
                defer {
                    for entry in scopedEntries where entry.acquired {
                        entry.url.stopAccessingSecurityScopedResource()
                    }
                }
                let resources = scopedEntries.map {
                    PickedDocumentResource(url: $0.url, hasSecurityScope: false, isTemporaryCopy: true)
                }
                if !resources.isEmpty {
                    if let resourcesCallback {
                        resourcesCallback(resources)
                    } else if let multi {
                        multi(resources.map(\.url))
                    } else if let single {
                        for res in resources {
                            single(res.url)
                        }
                    }
                }
            } else {
                // Keep security scopes alive and transfer ownership to WorkspaceManager via `PickedDocumentResource`.
                let resources = scopedEntries.map {
                    PickedDocumentResource(url: $0.url, hasSecurityScope: $0.acquired, isTemporaryCopy: false)
                }
                guard !resources.isEmpty else { return }
                if let resourcesCallback {
                    resourcesCallback(resources)
                } else if let multi {
                    multi(resources.map(\.url))
                } else if let single {
                    for res in resources {
                        single(res.url)
                    }
                }
            }
        }
    }

    public nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor [weak self] () -> Void in
            self?.clearDocumentPickerCallbacks()
        }
    }

    // MARK: - iOS 15 Compatible UIKit Text Input Alert
    public func presentTextInputAlert(
        title: String,
        message: String? = nil,
        initialText: String = "",
        placeholder: String = "",
        confirmTitle: String,
        cancelTitle: String,
        isDestructive: Bool = false,
        keyboardType: UIKeyboardType = .default,
        onConfirm: @escaping (String) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = initialText
            textField.placeholder = placeholder
            textField.keyboardType = keyboardType
            textField.autocorrectionType = .no
            textField.autocapitalizationType = .none
            textField.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in
            onCancel?()
        })
        alert.addAction(
            UIAlertAction(title: confirmTitle, style: isDestructive ? .destructive : .default) { [weak alert] _ in
                let value = alert?.textFields?.first?.text ?? initialText
                onConfirm(value)
            }
        )
        // Defer slightly so UIKit .contextMenu / Menu dismissal on iOS 15 finishes cleanly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] () -> Void in
            self?.presentAlertWhenReady(alert, retries: 24, onAborted: onCancel)
        }
    }

    // MARK: - Photo Library Vision Picker (PHPicker - iOS 14+/15+ Compatible)
    public func presentPhotoLibraryPicker(
        maxCount: Int = 4,
        initialDelay: TimeInterval = 0.08,
        onPickImages: @escaping ([UIImage]) -> Void
    ) {
        activePickImages = onPickImages
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = maxCount
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.presentationController?.delegate = self
        activePresentedController = picker
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] () -> Void in
                self?.presentWhenReady(picker)
            }
        } else {
            presentWhenReady(picker)
        }
    }

    public nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task { @MainActor [weak self] () -> Void in
            picker.dismiss(animated: true)
            self?.activePresentedController = nil
        }
        guard !results.isEmpty else {
            Task { @MainActor [weak self] () -> Void in
                self?.activePickImages = nil
            }
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var loaded: [(Int, UIImage)] = []

        for (index, result) in results.enumerated() {
            let provider = result.itemProvider
            guard provider.canLoadObject(ofClass: UIImage.self) else { continue }
            group.enter()
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                if let img = object as? UIImage {
                    lock.lock()
                    loaded.append((index, img))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] () -> Void in
            let sorted = loaded.sorted { $0.0 < $1.0 }.map { $0.1 }
            Task { @MainActor [weak self] () -> Void in
                guard let self else { return }
                let cb = self.activePickImages
                self.activePickImages = nil
                self.activePresentedController = nil
                if !sorted.isEmpty {
                    cb?(sorted)
                }
            }
        }
    }

    // MARK: - Camera Vision Picker (UIImagePickerController - iOS 15+ Compatible)
    public func presentCameraPicker(
        initialDelay: TimeInterval = 0.08,
        onUnavailable: (() -> Void)? = nil,
        onPickImage: @escaping (UIImage) -> Void
    ) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            onUnavailable?()
            return
        }
        activePickCameraImage = onPickImage
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = self
        picker.presentationController?.delegate = self
        activePresentedController = picker
        if initialDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + initialDelay) { [weak self] () -> Void in
                self?.presentWhenReady(picker)
            }
        } else {
            presentWhenReady(picker)
        }
    }

    public nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        Task { @MainActor [weak self] () -> Void in
            picker.dismiss(animated: true)
            guard let self else { return }
            let cb = self.activePickCameraImage
            self.activePickCameraImage = nil
            self.activePresentedController = nil
            if let image {
                cb?(image)
            }
        }
    }

    public nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor [weak self] () -> Void in
            picker.dismiss(animated: true)
            self?.activePickCameraImage = nil
            self?.activePresentedController = nil
        }
    }

    public nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] () -> Void in
            self?.clearAllPendingCallbacks()
        }
    }

    private func clearDocumentPickerCallbacks() {
        activePickSingle = nil
        activePickMultiple = nil
        activePickResources = nil
        activePresentedController = nil
    }

    private func clearAllPendingCallbacks() {
        clearDocumentPickerCallbacks()
        activePickImages = nil
        activePickCameraImage = nil
    }

    // MARK: - Vision Image Compression Helper
    public nonisolated static func downscaleAndCompress(
        _ image: UIImage,
        maxDimension: CGFloat = 1280,
        quality: CGFloat = 0.80
    ) -> (data: Data, width: Int, height: Int)? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 0 && pixelHeight > 0 else { return nil }
        let maxSide = max(pixelWidth, pixelHeight)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1.0
        let targetSize = CGSize(
            width: max(1, floor(pixelWidth * scale)),
            height: max(1, floor(pixelHeight * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
        return (data, Int(targetSize.width), Int(targetSize.height))
    }
}
