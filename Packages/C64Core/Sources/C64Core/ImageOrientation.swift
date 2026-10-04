/// How a picture's stored pixels turn into the picture as it is seen: the
/// eight orientations of TIFF and EXIF (tag 274), with their numbers, which
/// Core Graphics' `CGImagePropertyOrientation` shares.
///
/// Cameras store pictures as their sensors read them, so a photo taken with
/// the phone upright is stored on its side. Each orientation says where the
/// stored picture's first row and first column are seen.
public enum ImageOrientation: UInt8, Hashable, Sendable, CaseIterable {
    /// The first row along the top and the first column down the left:
    /// stored as seen.
    case up = 1
    /// The first row along the top and the first column down the right:
    /// mirrored left to right.
    case upMirrored = 2
    /// The first row along the bottom and the first column down the right:
    /// upside down.
    case down = 3
    /// The first row along the bottom and the first column down the left:
    /// mirrored top to bottom.
    case downMirrored = 4
    /// The first row down the left and the first column along the top.
    case leftMirrored = 5
    /// The first row down the right and the first column along the top: the
    /// stored picture is seen after a quarter turn clockwise.
    case right = 6
    /// The first row down the right and the first column along the bottom.
    case rightMirrored = 7
    /// The first row down the left and the first column along the bottom:
    /// the stored picture is seen after a quarter turn anticlockwise.
    case left = 8

    /// Whether the stored picture's rows run up and down the picture as
    /// seen, so that its width is the stored height.
    public var swapsAxes: Bool { rawValue >= 5 }

    /// The same, then mirrored left to right as seen: a front camera's
    /// pictures as a mirror shows them.
    public var mirrored: ImageOrientation {
        switch self {
        case .up: .upMirrored
        case .upMirrored: .up
        case .down: .downMirrored
        case .downMirrored: .down
        case .leftMirrored: .right
        case .right: .leftMirrored
        case .rightMirrored: .left
        case .left: .rightMirrored
        }
    }

    /// Where a point of the picture as seen lies in the stored picture. Both
    /// points go from 0 to 1 across and down, from the top left corner.
    public func storedPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        switch self {
        case .up: (x, y)
        case .upMirrored: (1 - x, y)
        case .down: (1 - x, 1 - y)
        case .downMirrored: (x, 1 - y)
        case .leftMirrored: (y, x)
        case .right: (y, 1 - x)
        case .rightMirrored: (1 - y, 1 - x)
        case .left: (1 - y, x)
        }
    }

    /// Where pixel (x, y) of a picture `width` × `height` pixels as seen is
    /// stored.
    func storedPixel(x: Int, y: Int, width: Int, height: Int) -> (x: Int, y: Int) {
        switch self {
        case .up: (x, y)
        case .upMirrored: (width - 1 - x, y)
        case .down: (width - 1 - x, height - 1 - y)
        case .downMirrored: (x, height - 1 - y)
        case .leftMirrored: (y, x)
        case .right: (y, width - 1 - x)
        case .rightMirrored: (height - 1 - y, width - 1 - x)
        case .left: (height - 1 - y, x)
        }
    }
}

extension Crop {
    /// The same part of a picture `width` × `height` pixels as seen, in the
    /// pixels of the picture as stored in an orientation.
    func stored(_ orientation: ImageOrientation, width: Double, height: Double) -> Crop {
        // How far the crop is from the right and bottom edges as seen.
        let (right, bottom) = (width - x - self.width, height - y - self.height)
        switch orientation {
        case .up: return self
        case .upMirrored: return Crop(x: right, y: y, width: self.width, height: self.height)
        case .down: return Crop(x: right, y: bottom, width: self.width, height: self.height)
        case .downMirrored: return Crop(x: x, y: bottom, width: self.width, height: self.height)
        case .leftMirrored: return Crop(x: y, y: x, width: self.height, height: self.width)
        case .right: return Crop(x: y, y: right, width: self.height, height: self.width)
        case .rightMirrored: return Crop(x: bottom, y: right, width: self.height, height: self.width)
        case .left: return Crop(x: bottom, y: x, width: self.height, height: self.width)
        }
    }
}
