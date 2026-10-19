import AppKit
import CoreGraphics
import ImageIO

enum ImageImporter {
    private static let maximumDimension = 2048

    static func load(_ url: URL) throws -> DesignObject {
        let sourceData = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw ImportError.unsupportedImage
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImportError.unsupportedImage
        }

        return try makeObject(image: image, label: url.deletingPathExtension().lastPathComponent)
    }

    static func load(svgData: Data, label: String) throws -> DesignObject {
        guard let vectorImage = NSImage(data: svgData),
              vectorImage.size.width > 0, vectorImage.size.height > 0 else {
            throw ImportError.unsupportedSVG
        }
        let scale = min(1, CGFloat(maximumDimension) / max(vectorImage.size.width, vectorImage.size.height))
        let width = max(1, Int((vectorImage.size.width * scale).rounded()))
        let height = max(1, Int((vectorImage.size.height * scale).rounded()))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                            isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else {
            throw ImportError.unsupportedSVG
        }
        NSGraphicsContext.saveGraphicsState()
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw ImportError.unsupportedSVG
        }
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        vectorImage.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { throw ImportError.unsupportedSVG }
        return try makeObject(image: image, label: label)
    }

    private static func makeObject(image: CGImage, label: String) throws -> DesignObject {

        let width = image.width, height = image.height
        guard width > 0, height > 0, width <= maximumDimension, height <= maximumDimension,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw ImportError.unsupportedImage
        }
        let bytesPerRow = width * 4
        var rgba = [UInt8](repeating: 255, count: bytesPerRow * height)
        let normalizedImage = rgba.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                          space: colorSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                return nil
            }
            // Preserve the decoder's image orientation. The preview and trace
            // pixels both come from this same raster, so neither gets an extra
            // vertical flip during import.
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return context.makeImage()
        }
        guard let normalizedImage else { throw ImportError.unsupportedImage }

        var grayscale = Data(count: width * height)
        grayscale.withUnsafeMutableBytes { output in
            guard let destination = output.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for pixelIndex in 0..<(width * height) {
                let sourceIndex = pixelIndex * 4
                let alpha = Double(rgba[sourceIndex + 3]) / 255
                let luminance = 0.2126 * Double(rgba[sourceIndex]) +
                                0.7152 * Double(rgba[sourceIndex + 1]) +
                                0.0722 * Double(rgba[sourceIndex + 2])
                // Transparent pixels are treated as white so they do not engrave.
                // The CGContext uses premultiplied alpha, so its RGB channels already include alpha.
                destination[pixelIndex] = UInt8(min(255, max(0, (luminance + 255 * (1 - alpha)).rounded())))
            }
        }

        guard let preview = NSBitmapImageRep(cgImage: normalizedImage).representation(using: .png, properties: [:]) else {
            throw ImportError.unsupportedImage
        }
        let scale = min(100 / Double(width), 100 / Double(height))
        let objectWidth = Double(width) * scale
        let objectHeight = Double(height) * scale
        return DesignObject(kind: .image, x: 20, y: 20, width: objectWidth, height: objectHeight,
                            label: label,
                            layerMode: .fill, imageData: preview, imagePixels: grayscale,
                            imagePixelWidth: width, imagePixelHeight: height,
                            minimumSpeed: 1000, maximumSpeed: 5000, variablePower: true)
    }

    enum ImportError: LocalizedError {
        case unsupportedImage, unsupportedSVG
        var errorDescription: String? {
            switch self {
            case .unsupportedImage: "This file could not be decoded as a PNG, JPG, or BMP image."
            case .unsupportedSVG: "This SVG could not be rendered as an image."
            }
        }
    }
}
