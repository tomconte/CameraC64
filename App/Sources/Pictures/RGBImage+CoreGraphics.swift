import C64Core
import CoreGraphics
import Foundation

extension RGBImage {
    /// An image's pixels, drawn into 8-bit sRGB.
    nonisolated init?(_ image: CGImage) {
        let (width, height) = (image.width, image.height)
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer in
            guard
                let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, layout: .rgba, bytes: bytes)
    }

    /// The picture as an image in sRGB.
    nonisolated var cgImage: CGImage? {
        let info: CGBitmapInfo =
            switch layout {
            case .rgb: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
            case .rgba: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
            case .bgra: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue).union(.byteOrder32Little)
            }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8 * layout.bytesPerPixel,
            bytesPerRow: width * layout.bytesPerPixel, space: space, bitmapInfo: info, provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
    }
}
