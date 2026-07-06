import SwiftUI
import Photos
import AppKit

// MARK: - Album model

struct PhotoAlbum: Identifiable, Hashable {
    let id: String
    let title: String
    let count: Int
}

/// Shared caching image manager for album-grid thumbnails.
let sharedPhotoImageManager = PHCachingImageManager()

// MARK: - Lazy Photos-library authorization + album listing

extension AppModel {
    /// Reflects the current system authorization without prompting; loads the
    /// album list automatically if access was already granted in a past launch.
    func refreshPhotosAuthStatus() {
        photosAuthStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if photosAuthStatus == .authorized || photosAuthStatus == .limited {
            loadPhotoAlbums()
        }
    }

    /// Triggers the system permission prompt (called from the sidebar's
    /// "Fotos-Mediathek verbinden…" row) and loads albums once granted.
    func requestPhotosAccess() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                self.photosAuthStatus = status
                if status == .authorized || status == .limited {
                    self.loadPhotoAlbums()
                }
            }
        }
    }

    /// Fetches "Alle Fotos" plus all regular user albums, sorted by title,
    /// skipping user albums that are empty.
    func loadPhotoAlbums() {
        Task.detached(priority: .userInitiated) {
            var albums: [PhotoAlbum] = []

            let smart = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumUserLibrary, options: nil)
            if let all = smart.firstObject {
                let count = all.estimatedAssetCount
                albums.append(PhotoAlbum(id: all.localIdentifier, title: "Alle Fotos", count: count == NSNotFound ? 0 : count))
            }

            var userAlbums: [PhotoAlbum] = []
            let regular = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
            regular.enumerateObjects { collection, _, _ in
                let count = collection.estimatedAssetCount
                guard count == NSNotFound || count > 0 else { return }
                userAlbums.append(PhotoAlbum(id: collection.localIdentifier,
                                             title: collection.localizedTitle ?? "Album",
                                             count: count == NSNotFound ? 0 : count))
            }
            userAlbums.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            albums.append(contentsOf: userAlbums)

            let result = albums
            await MainActor.run {
                self.photoAlbums = result
            }
        }
    }

    /// Loads (newest-first, images only) the assets of an album into `albumAssets`.
    func loadAlbumAssets(albumID: String) {
        albumAssets = []
        Task.detached(priority: .userInitiated) {
            guard let collection = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else {
                return
            }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = 200
            let fetchResult = PHAsset.fetchAssets(in: collection, options: options)
            var assets: [PHAsset] = []
            fetchResult.enumerateObjects { asset, _, _ in assets.append(asset) }

            let result = assets
            await MainActor.run {
                self.albumAssets = result
            }
        }
    }

    /// Loads the full-resolution image for a tapped asset and feeds it through
    /// the normal `applySource` pipeline.
    func selectAlbumAsset(_ asset: PHAsset) {
        let target = effectiveAppearance
        isLoadingSource = true
        errorMessage = nil

        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false

        let assetID = asset.localIdentifier
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            Task { @MainActor in
                defer { self.isLoadingSource = false }
                guard let data,
                      let image = NSImage(data: data),
                      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    self.errorMessage = "Bild konnte nicht aus Fotos geladen werden."
                    return
                }
                let baseName = "photos-\(assetID.prefix(8))"
                self.applySource(cg, photoID: assetID, baseName: baseName,
                                  attribution: "Aus Fotos-Mediathek", attributionURL: nil,
                                  to: target)
            }
        }
    }
}

// MARK: - Export into the Photos library

enum PhotosExportError: LocalizedError {
    case denied, albumFailed, addFailed

    var errorDescription: String? {
        switch self {
        case .denied:
            return "Kein Zugriff auf Fotos. Bitte in den Systemeinstellungen → Datenschutz & Sicherheit → Fotos den Zugriff für Blur Wallpaper Maker erlauben."
        case .albumFailed:
            return "Das Album „Wallpaper Maker“ konnte nicht angelegt werden."
        case .addFailed:
            return "Das Wallpaper konnte nicht in Fotos gesichert werden."
        }
    }
}

extension AppModel {
    private static let albumName = "Wallpaper Maker"

    /// Renders the dynamic HEIC to a temp file, then imports it into a
    /// (created-if-needed) "Wallpaper Maker" album in the Photos library.
    func saveToPhotosLibrary() {
        errorMessage = nil
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("photos-export-\(UUID().uuidString.prefix(8)).heic")
            try writeOutput(to: url)
            Task {
                do {
                    try await Self.addHEIC(at: url, toAlbumNamed: Self.albumName)
                    await MainActor.run { self.statusMessage = "In Fotos gesichert (Album „Wallpaper Maker“)." }
                } catch {
                    await MainActor.run { self.errorMessage = error.localizedDescription }
                }
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func addHEIC(at url: URL, toAlbumNamed name: String) async throws {
        // .readWrite (not .addOnly): fetching and creating the album requires read access.
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        guard status == .authorized || status == .limited else {
            throw PhotosExportError.denied
        }

        let album = try await findOrCreateAlbum(named: name)

        try await PHPhotoLibrary.shared().performChanges {
            guard let creationRequest = PHAssetCreationRequest.creationRequestForAssetFromImage(atFileURL: url) else {
                return
            }
            if let albumChangeRequest = PHAssetCollectionChangeRequest(for: album),
               let placeholder = creationRequest.placeholderForCreatedAsset {
                albumChangeRequest.addAssets([placeholder] as NSArray)
            }
        }
    }

    private static func findOrCreateAlbum(named name: String) async throws -> PHAssetCollection {
        let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var existing: PHAssetCollection?
        fetch.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == name {
                existing = collection
                stop.pointee = true
            }
        }
        if let existing { return existing }

        var placeholder: PHObjectPlaceholder?
        try await PHPhotoLibrary.shared().performChanges {
            let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: name)
            placeholder = request.placeholderForCreatedAssetCollection
        }
        guard let identifier = placeholder?.localIdentifier else { throw PhotosExportError.albumFailed }
        let result = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil)
        guard let album = result.firstObject else { throw PhotosExportError.albumFailed }
        return album
    }
}
