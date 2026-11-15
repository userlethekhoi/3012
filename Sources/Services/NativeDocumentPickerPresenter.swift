import Foundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Native UIKit presenter that avoids SwiftUI `.sheet` / `UIMenu` / `CommandPaletteSheet` dismissal collisions
/// when opening system Files/Folders (`UIDocumentPickerViewController`), Photo Library (`PHPickerViewController`),
/// or Camera (`UIImagePickerController`), while capturing security-scoped URL access synchronously in the delegate callback.
@MainActor
public final class NativeDocumentPickerPresenter: NSObject, UIDocumentPickerDelegate, PHPickerViewControllerDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public static let shared = NativeDocumentPickerPresenter()

    private var activePickSingle: ((URL) -> Void)?
    private var activePickMultiple: (([URL]) -> Void)?
    private var activePickImages: (([UIImage]) -> Void)?
    private var activePickCameraImage: ((UIImage) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Top-Most Presenter Discovery & Menu-Safe Presentation
    private func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        return activeScene?.windows.first(where: { $0.isKeyWindow }) ?? activeScene?.windows.first
    }

    private func topMostPresenter() -> UIViewController? {
        guard var top = keyWindow()?.rootViewController else { return nil }
        while let presented = top.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    private func presentWhenReady(_ viewController: UIViewController, retries: Int = 10) {
        if let top = topMostPresenter() {
            if top.isBeingDismissed || top.presentedViewController != nil {
                if retries > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                        self?.presentWhenReady(viewController, retries: retries - 1)
                    }
                    return
                }
            }
            top.present(viewController, animated: true)
            return
        }

        if retries > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                self?.presentWhenReady(viewController, retries: retries - 1)
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
        activePickSingle = onPickURL
        activePickMultiple = onPickURLs

        let picker: UIDocumentPickerViewController
        switch mode {
        case .folder:
            // Important on iOS 15-26: use the convenience initializer without `asCopy:` for `.folder`
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
            picker.allowsMultipleSelection = false
        case .singleFile:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .data, .content, .text, .sourceCode],
                asCopy: false
            )
            picker.allowsMultipleSelection = true
        case .zip:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.zip, .archive, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
        case .themeJSON:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.json, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = false
        }
        picker.shouldShowFileExtensions = true
        picker.delegate = self

        let launch: () -> Void = { [weak self] in
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
        Task { @MainActor [weak self] in
            defer {
                // Release temporary delegate scope after WorkspaceManager has acquired/copied what it needs
                for entry in scopedEntries where entry.acquired {
                    entry.url.stopAccessingSecurityScopedResource()
                }
            }
            guard let self else { return }
            let single = self.activePickSingle
            let multi = self.activePickMultiple
            self.activePickSingle = nil
            self.activePickMultiple = nil
            let rawURLs = scopedEntries.map(\.url)
            guard !rawURLs.isEmpty else { return }
            if let multi {
                multi(rawURLs)
            } else if let single {
                for url in rawURLs {
                    single(url)
                }
            }
        }
    }

    public nonisolated func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        Task { @MainActor [weak self] in
            self?.activePickSingle = nil
            self?.activePickMultiple = nil
        }
    }

    // MARK: - Photo Library Vision Picker (PHPicker - iOS 14+/15+ Compatible)
    public func presentPhotoLibraryPicker(maxCount: Int = 4, onPickImages: @escaping ([UIImage]) -> Void) {
        activePickImages = onPickImages
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = maxCount
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        presentWhenReady(picker)
    }

    public nonisolated func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        Task { @MainActor in
            picker.dismiss(animated: true)
        }
        guard !results.isEmpty else {
            Task { @MainActor [weak self] in
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

        group.notify(queue: .main) { [weak self] in
            let sorted = loaded.sorted { $0.0 < $1.0 }.map { $0.1 }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cb = self.activePickImages
                self.activePickImages = nil
                if !sorted.isEmpty {
                    cb?(sorted)
                }
            }
        }
    }

    // MARK: - Camera Vision Picker (UIImagePickerController - iOS 15+ Compatible)
    public func presentCameraPicker(onPickImage: @escaping (UIImage) -> Void) {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        activePickCameraImage = onPickImage
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.delegate = self
        presentWhenReady(picker)
    }

    public nonisolated func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            guard let self else { return }
            let cb = self.activePickCameraImage
            self.activePickCameraImage = nil
            if let image {
                cb?(image)
            }
        }
    }

    public nonisolated func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        Task { @MainActor [weak self] in
            picker.dismiss(animated: true)
            self?.activePickCameraImage = nil
        }
    }

    // MARK: - Vision Image Compression Helper
    public nonisolated static func downscaleAndCompress(
        _ image: UIImage,
        maxDimension: CGFloat = 1280,
        quality: CGFloat = 0.80
    ) -> (data: Data, width: Int, height: Int)? {
        let origSize = image.size
        guard origSize.width > 0 && origSize.height > 0 else { return nil }
        let maxSide = max(origSize.width, origSize.height)
        let scale = maxSide > maxDimension ? (maxDimension / maxSide) : 1.0
        let targetSize = CGSize(
            width: max(1, floor(origSize.width * scale)),
            height: max(1, floor(origSize.height * scale))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
        return (data, Int(targetSize.width), Int(targetSize.height))
    }
}
