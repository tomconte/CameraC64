import C64Core
import CoreGraphics
import Foundation
import ImageIO
import UIKit

/// A photo to convert: a shot, or one from the library.
///
/// It keeps the pixels at full size and as stored, so the converter averages
/// them in linear light itself, with the orientation that turns them as they
/// are seen. Photos are never shrunk first by ImageIO, which would average
/// them in sRGB.
nonisolated struct Photo: Identifiable, @unchecked Sendable {
    let id = UUID()
    /// The pixels, as stored.
    let image: RGBImage
    /// How they are seen: the photo's own orientation, then mirrored for the
    /// front camera, whose shots look as in a mirror, like its viewfinder.
    let orientation: ImageOrientation
    /// A smaller copy, upright but never mirrored, to show the original.
    /// (CGImage is immutable, so threads can share it.)
    let preview: CGImage
    /// Whether the picture mirrors the photo.
    let mirrored: Bool

    /// The preview's longer side, in pixels: sharp on the TV at any size.
    static let previewSize = 1200

    /// Decodes a photo file, such as a HEIC or a JPEG.
    init?(data: Data, mirrored: Bool) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let stored = CGImageSourceCreateImageAtIndex(source, 0, nil), let image = RGBImage(stored)
        else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let number = properties?[kCGImagePropertyOrientation] as? NSNumber
        let orientation = number.flatMap { ImageOrientation(rawValue: $0.uint8Value) } ?? .up
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.previewSize,
        ]
        guard let preview = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        self.image = image
        self.orientation = mirrored ? orientation.mirrored : orientation
        self.preview = preview
        self.mirrored = mirrored
    }
}

extension Photo {
    /// The bundled sample photo, for previews and tests.
    @MainActor static var sample: Photo? {
        UIImage(named: "SamplePhoto")?.pngData().flatMap { Photo(data: $0, mirrored: false) }
    }
}
