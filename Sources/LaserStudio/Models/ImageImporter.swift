import AppKit
import CoreGraphics
import ImageIO

enum ImageImporter {
    private static let maximumDimension = 2048

    static func load(_ url: URL, workspace: CGSize = CGSize(width: 400, height: 400)) throws -> DesignObject {
        let sourceData = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw ImportError.unsupportedImage
        }
        let dpi = extractDPI(from: source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumDimension
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImportError.unsupportedImage
        }

        return try makeObject(image: image, label: url.deletingPathExtension().lastPathComponent, sourceDPI: dpi, workspace: workspace)
    }

    static func load(svgData: Data, label: String, workspace: CGSize = CGSize(width: 400, height: 400)) throws -> DesignObject {
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
        return try makeObject(image: image, label: label, sourceDPI: 96.0, workspace: workspace)
    }

    private static func extractDPI(from source: CGImageSource) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return 96.0
        }
        if let dpiW = (props[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue, dpiW > 10, dpiW < 4800 {
            return dpiW
        }
        return 96.0
    }

    private static func makeObject(
        image: CGImage,
        label: String,
        sourceDPI: Double = 96.0,
        workspace: CGSize = CGSize(width: 400, height: 400)
    ) throws -> DesignObject {
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
                destination[pixelIndex] = UInt8(min(255, max(0, (luminance + 255 * (1 - alpha)).rounded())))
            }
        }

        guard let preview = NSBitmapImageRep(cgImage: normalizedImage).representation(using: .png, properties: [:]) else {
            throw ImportError.unsupportedImage
        }

        // LightBurn physical sizing from embedded DPI, clamped to fit workspace and centered
        let effectiveDPI = max(36.0, sourceDPI)
        var objectWidth = Double(width) * 25.4 / effectiveDPI
        var objectHeight = Double(height) * 25.4 / effectiveDPI
        let maxW = max(40.0, Double(workspace.width) * 0.85)
        let maxH = max(40.0, Double(workspace.height) * 0.85)
        if objectWidth > maxW || objectHeight > maxH {
            let fitScale = min(maxW / objectWidth, maxH / objectHeight)
            objectWidth *= fitScale
            objectHeight *= fitScale
        }
        if objectWidth < 8.0 && objectHeight < 8.0 {
            let scale = min(100 / Double(width), 100 / Double(height))
            objectWidth = Double(width) * scale
            objectHeight = Double(height) * scale
        }
        let posX = max(0, (Double(workspace.width) - objectWidth) / 2.0)
        let posY = max(0, (Double(workspace.height) - objectHeight) / 2.0)

        return DesignObject(
            kind: .image,
            x: posX,
            y: posY,
            width: objectWidth,
            height: objectHeight,
            label: label,
            color: LightBurnPalette.layers[0].color,
            layerMode: .fill,
            imageData: preview,
            imagePixels: grayscale,
            imagePixelWidth: width,
            imagePixelHeight: height,
            minimumSpeed: 1000,
            maximumSpeed: 5000,
            variablePower: true,
            imageDitherMode: .grayscale,
            imageDPI: 254.0
        )
    }

    /// Converts any vector or text DesignObject into a raster `.image` layer ("Convert to Bitmap" in LightBurn).
    static func convertToBitmap(_ object: DesignObject, dpi: Double = 254.0) -> DesignObject? {
        guard object.kind != .image else { return object }
        let subpaths = ShapeGeometry.workspaceSubpaths(for: object)
        let allPoints = subpaths.flatMap(\.points)
        guard let minX = allPoints.map(\.x).min(), let maxX = allPoints.map(\.x).max(),
              let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max() else { return nil }
        let pad = 1.0
        let boxW = max(2.0, Double(maxX - minX) + pad * 2)
        let boxH = max(2.0, Double(maxY - minY) + pad * 2)
        let pxPerMM = min(12.0, max(2.0, dpi / 25.4))
        let pixelW = max(16, min(1200, Int((boxW * pxPerMM).rounded())))
        let pixelH = max(16, min(1200, Int((boxH * pxPerMM).rounded())))
        let rgbaBytesPerRow = pixelW * 4
        var rgba = [UInt8](repeating: 255, count: pixelH * rgbaBytesPerRow)
        guard let ctx = CGContext(
            data: &rgba, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: rgbaBytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: pixelW, height: pixelH))
        ctx.translateBy(x: 0, y: CGFloat(pixelH))
        ctx.scaleBy(x: CGFloat(Double(pixelW) / boxW), y: -CGFloat(Double(pixelH) / boxH))
        ctx.translateBy(x: -(minX - CGFloat(pad)), y: -(minY - CGFloat(pad)))

        let cgPath = CGMutablePath()
        for sub in subpaths where sub.points.count >= 2 {
            cgPath.move(to: sub.points[0])
            for pt in sub.points.dropFirst() { cgPath.addLine(to: pt) }
            if sub.isClosed { cgPath.closeSubpath() }
        }
        ctx.setStrokeColor(NSColor.black.cgColor)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.setLineWidth(0.35)
        ctx.addPath(cgPath)
        if object.layerMode == .line {
            ctx.strokePath()
        } else {
            ctx.drawPath(using: .eoFillStroke)
        }
        guard let cgImage = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let pngData = rep.representation(using: .png, properties: [:])
        var gray = [UInt8](repeating: 255, count: pixelW * pixelH)
        for i in 0..<(pixelW * pixelH) {
            gray[i] = rgba[i * 4]
        }
        return DesignObject(
            kind: .image,
            x: max(0, Double(minX) - pad),
            y: max(0, Double(minY) - pad),
            width: boxW,
            height: boxH,
            label: "\(object.label) Bitmap",
            color: object.color,
            power: object.power,
            speed: object.speed,
            burnEnabled: object.burnEnabled,
            layerMode: .fill,
            imageData: pngData,
            imagePixels: Data(gray),
            imagePixelWidth: pixelW,
            imagePixelHeight: pixelH,
            minimumSpeed: 1000,
            maximumSpeed: max(2000, object.speed),
            variablePower: true,
            imageDitherMode: .stucki,
            imageDPI: dpi
        )
    }

    /// Applies LightBurn's Adjust Image pipeline (Brightness, Contrast, Gamma, Unsharp Mask Enhance, Invert, and Dithering)
    static func processedGrayscale(for object: DesignObject) -> [UInt8] {
        guard let rawData = object.imagePixels,
              object.imagePixelWidth > 0, object.imagePixelHeight > 0,
              rawData.count >= object.imagePixelWidth * object.imagePixelHeight else {
            return []
        }
        let w = object.imagePixelWidth
        let h = object.imagePixelHeight
        let src = [UInt8](rawData)

        let hasToneAdjustments =
            abs(object.imageBrightness) > 0.01 ||
            abs(object.imageContrast) > 0.01 ||
            abs(object.imageGamma - 1.0) > 0.01 ||
            object.imageEnhanceRadius > 0.1 ||
            object.imageInverted ||
            (!object.imagePassThrough && object.imageDitherMode != .grayscale)

        if !hasToneAdjustments {
            return src
        }

        let brightnessDelta = (object.imageBrightness / 100.0) * 255.0
        let contrastVal = max(-99.0, min(99.0, object.imageContrast)) * 2.55
        let contrastFactor = (259.0 * (contrastVal + 255.0)) / (255.0 * (259.0 - contrastVal))
        let gamma = max(0.1, min(5.0, object.imageGamma))
        let invGamma = 1.0 / gamma

        var lut = [UInt8](repeating: 0, count: 256)
        for v in 0..<256 {
            var px = Double(v)
            if object.imageInverted { px = 255.0 - px }
            px = 255.0 * pow(px / 255.0, invGamma)
            px = contrastFactor * (px - 128.0) + 128.0 + brightnessDelta
            lut[v] = UInt8(min(255, max(0, Int(px.rounded()))))
        }

        var buf = [Double](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            buf[i] = Double(lut[Int(src[i])])
        }

        let radius = Int(min(10, max(0, object.imageEnhanceRadius.rounded())))
        if radius >= 1 && object.imageEnhanceAmount > 1 && w > radius * 2 && h > radius * 2 {
            let amount = object.imageEnhanceAmount / 100.0
            var blurred = buf
            for y in radius..<(h - radius) {
                for x in radius..<(w - radius) {
                    var sum = 0.0
                    var count = 0.0
                    for ky in -radius...radius {
                        let rowBase = (y + ky) * w
                        for kx in -radius...radius {
                            sum += buf[rowBase + x + kx]
                            count += 1.0
                        }
                    }
                    blurred[y * w + x] = sum / count
                }
            }
            for i in 0..<(w * h) {
                let diff = buf[i] - blurred[i]
                buf[i] = min(255.0, max(0.0, buf[i] + diff * amount))
            }
        }

        if object.imagePassThrough || object.imageDitherMode == .grayscale {
            return buf.map { UInt8(min(255, max(0, Int($0.rounded())))) }
        }

        return applyDither(buf, width: w, height: h, mode: object.imageDitherMode)
    }

    static func applyDither(_ input: [Double], width w: Int, height h: Int, mode: ImageDitherMode) -> [UInt8] {
        var work = input
        var out = [UInt8](repeating: 255, count: w * h)

        switch mode {
        case .grayscale:
            for i in 0..<(w * h) { out[i] = UInt8(min(255, max(0, Int(work[i].rounded())))) }
        case .threshold:
            for i in 0..<(w * h) { out[i] = work[i] < 128.0 ? 0 : 255 }
        case .ordered:
            let bayer4x4: [[Double]] = [
                [ 0,  8,  2, 10],
                [12,  4, 14,  6],
                [ 3, 11,  1,  9],
                [15,  7, 13,  5]
            ]
            for y in 0..<h {
                for x in 0..<w {
                    let threshold = (bayer4x4[y & 3][x & 3] + 0.5) * 16.0
                    out[y * w + x] = work[y * w + x] < threshold ? 0 : 255
                }
            }
        case .newsprint:
            let cluster4x4: [[Double]] = [
                [12,  5,  6, 13],
                [ 4,  0,  1,  7],
                [11,  3,  2,  8],
                [15, 10,  9, 14]
            ]
            for y in 0..<h {
                for x in 0..<w {
                    let threshold = (cluster4x4[y & 3][x & 3] + 0.5) * 16.0
                    out[y * w + x] = work[y * w + x] < threshold ? 0 : 255
                }
            }
        case .halftone:
            let angle = 22.5 * Double.pi / 180.0
            let cosA = cos(angle), sinA = sin(angle)
            let freq = Double.pi * 2.0 / 5.0
            for y in 0..<h {
                for x in 0..<w {
                    let u = Double(x) * cosA - Double(y) * sinA
                    let v = Double(x) * sinA + Double(y) * cosA
                    let wave = (sin(u * freq) + cos(v * freq) + 2.0) * 0.25 * 255.0
                    out[y * w + x] = work[y * w + x] < wave ? 0 : 255
                }
            }
        case .sketch:
            for y in 1..<max(1, h - 1) {
                for x in 1..<max(1, w - 1) {
                    let gx = -work[(y-1)*w+(x-1)] + work[(y-1)*w+(x+1)] - 2*work[y*w+(x-1)] + 2*work[y*w+(x+1)] - work[(y+1)*w+(x-1)] + work[(y+1)*w+(x+1)]
                    let gy = -work[(y-1)*w+(x-1)] - 2*work[(y-1)*w+x] - work[(y-1)*w+(x+1)] + work[(y+1)*w+(x-1)] + 2*work[(y+1)*w+x] + work[(y+1)*w+(x+1)]
                    let mag = hypot(gx, gy)
                    out[y * w + x] = mag > 95.0 ? 0 : 255
                }
            }
        case .dither, .atkinson, .stucki, .jarvis, .burkes:
            let kernel: [(dx: Int, dy: Int, weight: Double)]
            switch mode {
            case .dither:
                kernel = [(1, 0, 7/16.0), (-1, 1, 3/16.0), (0, 1, 5/16.0), (1, 1, 1/16.0)]
            case .atkinson:
                kernel = [(1, 0, 1/8.0), (2, 0, 1/8.0), (-1, 1, 1/8.0), (0, 1, 1/8.0), (1, 1, 1/8.0), (0, 2, 1/8.0)]
            case .stucki:
                kernel = [
                    (1, 0, 8/42.0), (2, 0, 4/42.0),
                    (-2, 1, 2/42.0), (-1, 1, 4/42.0), (0, 1, 8/42.0), (1, 1, 4/42.0), (2, 1, 2/42.0),
                    (-2, 2, 1/42.0), (-1, 2, 2/42.0), (0, 2, 4/42.0), (1, 2, 2/42.0), (2, 2, 1/42.0)
                ]
            case .jarvis:
                kernel = [
                    (1, 0, 7/48.0), (2, 0, 5/48.0),
                    (-2, 1, 3/48.0), (-1, 1, 5/48.0), (0, 1, 7/48.0), (1, 1, 5/48.0), (2, 1, 3/48.0),
                    (-2, 2, 1/48.0), (-1, 2, 3/48.0), (0, 2, 5/48.0), (1, 2, 3/48.0), (2, 2, 1/48.0)
                ]
            case .burkes:
                kernel = [
                    (1, 0, 8/32.0), (2, 0, 4/32.0),
                    (-2, 1, 2/32.0), (-1, 1, 4/32.0), (0, 1, 8/32.0), (1, 1, 4/32.0), (2, 1, 2/32.0)
                ]
            default:
                kernel = []
            }
            for y in 0..<h {
                let serpentine = (y & 1) == 1
                let xRange = serpentine ? Array((0..<w).reversed()) : Array(0..<w)
                for x in xRange {
                    let idx = y * w + x
                    let oldVal = work[idx]
                    let newVal: Double = oldVal < 128.0 ? 0.0 : 255.0
                    out[idx] = UInt8(newVal)
                    let err = oldVal - newVal
                    let dir = serpentine ? -1 : 1
                    for item in kernel {
                        let nx = x + item.dx * dir
                        let ny = y + item.dy
                        if nx >= 0 && nx < w && ny >= 0 && ny < h {
                            work[ny * w + nx] += err * item.weight
                        }
                    }
                }
            }
        }
        return out
    }

    static func processedNSImage(for object: DesignObject) -> NSImage? {
        let w = object.imagePixelWidth
        let h = object.imagePixelHeight
        guard w > 0, h > 0 else { return nil }
        var gray = processedGrayscale(for: object)
        guard gray.count >= w * h else { return nil }
        guard let ctx = CGContext(
            data: &gray, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ), let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: w, height: h))
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
