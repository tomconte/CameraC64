import Foundation
import Photos

/// Saves pictures to Photos, where the app may only add them (plan, section
/// 9): the picture as on TV, as a PNG file.
nonisolated enum PhotoLibrary {
    /// Why a picture was not saved.
    nonisolated enum Failure: Error, Equatable {
        /// The user, or the phone's restrictions, keep the app from adding
        /// photos.
        case notAllowed
        /// Photos would not take the picture.
        case notSaved

        /// What the TV says about it.
        var detail: String {
            switch self {
            case .notAllowed: "Allow Camera C64 to add photos in Settings"
            case .notSaved: "Photos would not take it"
            }
        }
    }

    /// Whether the app may add photos, asking the user first if they have
    /// not been asked yet.
    static func canAdd() async -> Bool {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        return status == .authorized || status == .limited
    }

    /// Adds a picture, as a PNG file, to Photos.
    static func add(png: Data) async throws(Failure) {
        guard await canAdd() else { throw .notAllowed }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: png, options: nil)
            }
        } catch {
            throw .notSaved
        }
    }
}
