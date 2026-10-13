import Photos
import PhotosUI
import ScreenshotKit
import UIKit

/// Read-only access to the Screenshots smart album. Photos are never moved or modified.
final nonisolated class PhotoLibraryService: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    static let shared = PhotoLibraryService()

    private let imageManager = PHCachingImageManager()
    /// The last final image delivered per asset, so a newly created view can draw it on its first frame.
    private let recentImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    private var onChange: (@MainActor () -> Void)?
    private var isObserving = false

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasAccess: Bool {
        authorizationStatus == .authorized || authorizationStatus == .limited
    }

    /// Only the photos the user picked are visible.
    var isLimited: Bool {
        authorizationStatus == .limited
    }

    /// Lets the user add more photos to a limited selection; the change observer picks up the result.
    @MainActor
    func presentLimitedLibraryPicker(from controller: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    /// Every screenshot the app can see, newest first.
    func fetchScreenshots() -> [AssetInfo] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "(mediaSubtypes & %ld) != 0", Int(PHAssetMediaSubtype.photoScreenshot.rawValue))
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: .image, options: options)
        return Self.assetInfos(result)
    }

    /// Photos' details for the given screenshots; ones no longer in Photos are left out.
    func assetInfos(for ids: [String]) -> [AssetInfo] {
        guard !ids.isEmpty else { return [] }
        return Self.assetInfos(PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil))
    }

    private static func assetInfos(_ result: PHFetchResult<PHAsset>) -> [AssetInfo] {
        var assets: [AssetInfo] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            assets.append(AssetInfo(
                id: asset.localIdentifier,
                createdAt: asset.creationDate ?? .distantPast,
                pixelWidth: asset.pixelWidth,
                pixelHeight: asset.pixelHeight
            ))
        }
        return assets
    }

    // MARK: - Cloud identifiers

    /// `localIdentifier` → `PHCloudIdentifier.stringValue`, for the screenshots iCloud Photos knows.
    /// Slow for large libraries; call it off the main thread.
    func cloudIdentifiers(for localIDs: [String]) -> [String: String] {
        guard !localIDs.isEmpty else { return [:] }
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: localIDs)
        return mappings.compactMapValues { try? $0.get().stringValue }
    }

    /// `PHCloudIdentifier.stringValue` → this device's `localIdentifier`, for the ones present here.
    func localIdentifiers(forCloud cloudIDs: [String]) -> [String: String] {
        guard !cloudIDs.isEmpty else { return [:] }
        let identifiers = cloudIDs.map(PHCloudIdentifier.init(stringValue:))
        let mappings = PHPhotoLibrary.shared().localIdentifierMappings(for: identifiers)
        var result: [String: String] = [:]
        for (cloud, local) in mappings {
            if let local = try? local.get() { result[cloud.stringValue] = local }
        }
        return result
    }

    func startObserving(_ handler: @escaping @MainActor () -> Void) {
        onChange = handler
        guard !isObserving else { return }
        isObserving = true
        PHPhotoLibrary.shared().register(self)
    }

    func photoLibraryDidChange(_: PHChange) {
        guard let onChange else { return }
        Task { @MainActor in onChange() }
    }

    // MARK: - Images

    private func fetchAsset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// The last image `images(for:)` finished loading for this asset, at whatever size it was requested.
    func cachedImage(for id: String) -> UIImage? {
        recentImages.object(forKey: id as NSString)
    }

    /// Streams a fast degraded image, then the final one. Cancelling the stream cancels the request.
    func images(for id: String, targetSize: CGSize, contentMode: PHImageContentMode = .aspectFill) -> AsyncStream<UIImage> {
        AsyncStream { continuation in
            guard let asset = fetchAsset(id) else {
                continuation.finish()
                return
            }
            let options = PHImageRequestOptions()
            options.deliveryMode = .opportunistic
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            let requestID = imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: contentMode, options: options) { [recentImages] image, info in
                let degraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                if let image {
                    if !degraded { recentImages.setObject(image, forKey: id as NSString, cost: Int(image.pixelArea) * 4) }
                    continuation.yield(image)
                }
                if !degraded { continuation.finish() }
            }
            continuation.onTermination = { [imageManager] _ in
                imageManager.cancelImageRequest(requestID)
            }
        }
    }

    /// Full-resolution image data for text recognition.
    func imageData(for id: String) async -> (Data, CGImagePropertyOrientation)? {
        guard let asset = fetchAsset(id) else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.version = .current
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, orientation, _ in
                continuation.resume(returning: data.map { ($0, orientation) })
            }
        }
    }
}
