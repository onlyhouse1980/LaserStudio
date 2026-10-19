import AppKit
import CoreText
import CoreGraphics

enum EngravingMode: String, CaseIterable, Identifiable {
    case line = "Line"
    case fill = "Fill"
    case offset = "Offset"
    var id: String { rawValue }
}

enum GCodeGenerator {
    static let ray5Workspace = 400.0
    static let ray5MaxFeedRate = 10000.0 // $110/$111 for this Ray5, mm/min

    static func make(objects: [DesignObject], material: String, sMax: Int, kerf: Double) throws -> [String] {
        guard (1...10000).contains(sMax) else { throw GenerationError.invalidSValue }
        let burnLayers = objects.filter(\.burnEnabled)
        guard !burnLayers.isEmpty else { throw GenerationError.noBurnLayers }
        var output = ["; LaserStudio · Longer RAY5 / GRBL", "; Material: \(material)", "; S max: \(sMax)", "G21", "G90", "G94", "M5"]
        for object in burnLayers {
            let bounds = rotatedBounds(for: object)
            guard bounds.minX >= 0, bounds.minY >= 0, object.width > 0, object.height > 0,
                  bounds.maxX <= ray5Workspace, bounds.maxY <= ray5Workspace else {
                throw GenerationError.outOfBounds(object.label)
            }
            let mode = object.layerMode
            let feed = min(ray5MaxFeedRate, max(40, object.speed))
            let power = Int((Double(sMax) * min(100, max(0, object.power)) / 100).rounded())
            if object.kind == .image {
                output += try raster(for: object, sMax: sMax, spacing: max(0.1, kerf))
                continue
            }
            var contours = paths(for: object)
            if mode == .offset && (object.kind == .text || object.kind == .path) {
                let step = max(0.1, kerf) * 2 / max(object.width, object.height)
                var scale = 1 - step
                let centerX = object.x + object.width / 2, centerY = object.y + object.height / 2
                while scale > 0.05 {
                    contours += contoursForOffset(paths(for: object), centerX: centerX, centerY: centerY, scale: scale)
                    scale -= step
                }
            } else if mode == .offset {
                var inset = max(0.1, kerf)
                while inset * 2 < min(object.width, object.height) {
                    var inner = object
                    inner.x += inset; inner.y += inset
                    inner.width -= inset * 2; inner.height -= inset * 2
                    contours += paths(for: inner)
                    inset += max(0.1, kerf)
                }
            }
            for contour in contours where contour.count > 1 {
                let first = contour[0]
                output.append("M5")
                output.append("G0 X\(fmt(first.x)) Y\(fmt(ray5Workspace - first.y))")
                // M4 is dynamic laser power; S is applied on moving blocks only.
                output.append("M4 S0")
                for point in contour.dropFirst() {
                    output.append("G1 X\(fmt(point.x)) Y\(fmt(ray5Workspace - point.y)) F\(fmt(feed)) S\(power)")
                }
                output.append("M5")
            }
            if mode == .fill && !(object.kind == .path && !object.pathIsClosed) {
                output += object.kind == .text
                    ? hatch(paths: contours, spacing: max(0.1, kerf), feed: feed, power: power)
                    : (object.rotation == 0
                        ? hatch(for: object, spacing: max(0.1, kerf), feed: feed, power: power)
                        : hatch(paths: contours, spacing: max(0.1, kerf), feed: feed, power: power))
            }
        }
        output.append("M5")
        return output
    }

    private static func paths(for object: DesignObject) -> [[CGPoint]] {
        let paths: [[CGPoint]]
        switch object.kind {
        case .rectangle:
            let a = CGPoint(x: object.x, y: object.y), b = CGPoint(x: object.x + object.width, y: object.y)
            let c = CGPoint(x: object.x + object.width, y: object.y + object.height), d = CGPoint(x: object.x, y: object.y + object.height)
            paths = [[a, b, c, d, a]]
        case .circle:
            paths = [ellipsePoints(object, steps: max(48, Int(max(object.width, object.height) * 2)))]
        case .text:
            paths = textPaths(object)
        case .line:
            paths = [[CGPoint(x: object.x, y: object.y), CGPoint(x: object.x + object.width, y: object.y + object.height)]]
        case .path:
            var points = object.pathPoints.map { CGPoint(x: object.x + $0.x, y: object.y + $0.y) }
            if object.pathIsClosed, let first = points.first, points.last != first { points.append(first) }
            paths = [points]
        case .image:
            paths = []
        }
        return paths.map { path in path.map { rotate($0, around: objectCenter(object), degrees: object.rotation) } }
    }

    private static func raster(for object: DesignObject, sMax: Int, spacing: Double) throws -> [String] {
        guard let pixels = object.imagePixels, object.imagePixelWidth > 0, object.imagePixelHeight > 0,
              pixels.count >= object.imagePixelWidth * object.imagePixelHeight else {
            throw GenerationError.invalidImage(object.label)
        }
        // Bound job size for very large designs while retaining the chosen fill spacing where possible.
        let pixelLimit = 300_000.0
        let areaLimitedSpacing = sqrt(object.width * object.height / pixelLimit)
        let pitch = max(spacing, areaLimitedSpacing)
        let columns = max(1, Int(ceil(object.width / pitch)))
        let rows = max(1, Int(ceil(object.height / pitch)))
        let stepX = object.width / Double(columns)
        let stepY = object.height / Double(rows)
        let lowSpeed = min(ray5MaxFeedRate, max(40, min(object.minimumSpeed, object.maximumSpeed)))
        let highSpeed = min(ray5MaxFeedRate, max(lowSpeed, max(object.minimumSpeed, object.maximumSpeed)))
        let maxPower = Int((Double(sMax) * min(100, max(0, object.power)) / 100).rounded())
        let imageWidth = object.imagePixelWidth
        let imageHeight = object.imagePixelHeight
        let data = [UInt8](pixels)
        var lines: [String] = []
        lines.reserveCapacity(rows * 4 + min(rows * columns, 300_000))

        for row in 0..<rows {
            let sourceY = min(imageHeight - 1, Int((Double(row) + 0.5) / Double(rows) * Double(imageHeight)))
            let reverse = row.isMultiple(of: 2)
            let startX = reverse ? object.width : 0
            let localY = (Double(row) + 0.5) * stepY
            let start = rotate(CGPoint(x: object.x + startX, y: object.y + localY), around: objectCenter(object), degrees: object.rotation)
            lines += ["M5", "G0 X\(fmt(start.x)) Y\(fmt(ray5Workspace - start.y))", "M4 S0"]

            var column = 0
            while column < columns {
                let sourceColumn = reverse ? columns - column - 1 : column
                let sourceX = min(imageWidth - 1, Int((Double(sourceColumn) + 0.5) / Double(columns) * Double(imageWidth)))
                let sourceGray = Double(data[sourceY * imageWidth + sourceX])
                let gray = object.imageInverted ? 255 - sourceGray : sourceGray
                let darkness = 1 - gray / 255
                let targetPower: Int
                if object.variablePower {
                    targetPower = Int((Double(maxPower) * darkness).rounded())
                } else {
                    targetPower = darkness >= 0.5 ? maxPower : 0
                }
                let targetFeed = Int((lowSpeed + (highSpeed - lowSpeed) * (gray / 255)).rounded())

                var runEnd = column + 1
                while runEnd < columns {
                    let runSourceColumn = reverse ? columns - runEnd - 1 : runEnd
                    let runSourceX = min(imageWidth - 1, Int((Double(runSourceColumn) + 0.5) / Double(columns) * Double(imageWidth)))
                    let sourceRunGray = Double(data[sourceY * imageWidth + runSourceX])
                    let runGray = object.imageInverted ? 255 - sourceRunGray : sourceRunGray
                    let runDarkness = 1 - runGray / 255
                    let runPower = object.variablePower
                        ? Int((Double(maxPower) * runDarkness).rounded())
                        : (runDarkness >= 0.5 ? maxPower : 0)
                    let runFeed = Int((lowSpeed + (highSpeed - lowSpeed) * (runGray / 255)).rounded())
                    guard runPower == targetPower, runFeed == targetFeed else { break }
                    runEnd += 1
                }
                let endX = reverse ? object.width - Double(runEnd) * stepX : Double(runEnd) * stepX
                let end = rotate(CGPoint(x: object.x + endX, y: object.y + localY), around: objectCenter(object), degrees: object.rotation)
                lines.append("G1 X\(fmt(end.x)) Y\(fmt(ray5Workspace - end.y)) F\(targetFeed) S\(targetPower)")
                column = runEnd
            }
            lines.append("M5")
        }
        return lines
    }

    private static func ellipsePoints(_ object: DesignObject, steps: Int) -> [CGPoint] {
        (0...steps).map { index in
            let angle = 2 * Double.pi * Double(index) / Double(steps)
            return CGPoint(x: object.x + object.width / 2 + cos(angle) * object.width / 2,
                           y: object.y + object.height / 2 + sin(angle) * object.height / 2)
        }
    }

    private static func objectCenter(_ object: DesignObject) -> CGPoint {
        CGPoint(x: object.x + object.width / 2, y: object.y + object.height / 2)
    }

    private static func rotate(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        guard degrees.truncatingRemainder(dividingBy: 360) != 0 else { return point }
        let radians = degrees * .pi / 180
        let dx = point.x - center.x, dy = point.y - center.y
        return CGPoint(x: center.x + dx * cos(radians) - dy * sin(radians),
                       y: center.y + dx * sin(radians) + dy * cos(radians))
    }

    private static func rotatedBounds(for object: DesignObject) -> CGRect {
        let center = objectCenter(object)
        let corners = [CGPoint(x: object.x, y: object.y), CGPoint(x: object.x + object.width, y: object.y),
                       CGPoint(x: object.x + object.width, y: object.y + object.height), CGPoint(x: object.x, y: object.y + object.height)]
            .map { rotate($0, around: center, degrees: object.rotation) }
        let minX = corners.map(\.x).min() ?? CGFloat(object.x)
        let maxX = corners.map(\.x).max() ?? CGFloat(object.x + object.width)
        let minY = corners.map(\.y).min() ?? CGFloat(object.y)
        let maxY = corners.map(\.y).max() ?? CGFloat(object.y + object.height)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func contoursForOffset(_ paths: [[CGPoint]], centerX: Double, centerY: Double, scale: Double) -> [[CGPoint]] {
        paths.map { path in path.map { CGPoint(x: centerX + ($0.x - centerX) * scale, y: centerY + ($0.y - centerY) * scale) } }
    }

    private static func textPaths(_ object: DesignObject) -> [[CGPoint]] {
        let metrics = SystemFontCatalog.fittedTextMetrics(label: object.label, family: object.fontFamily,
                                                           width: object.width, height: object.height,
                                                           bold: object.fontBold, italic: object.fontItalic)
        let font = metrics.font
        let attributed = NSAttributedString(string: object.label, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        var contours: [[CGPoint]] = []
        let scale = Double(metrics.scale)
        let ascent = Double(metrics.ascent)
        let horizontalOffset = object.x + (object.width - Double(metrics.lineWidth) * scale) / 2
        let verticalOffset = object.y + (object.height - Double(metrics.ascent + metrics.descent) * scale) / 2
        for runValue in CTLineGetGlyphRuns(line) as! [CTRun] {
            let run = runValue
            let count = CTRunGetGlyphCount(run)
            var glyphs = Array(repeating: CGGlyph(), count: count)
            var positions = Array(repeating: CGPoint.zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            for index in 0..<count {
                guard let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                let transform = CGAffineTransform(translationX: positions[index].x, y: positions[index].y)
                let positioned = glyphPath.copy(using: [transform]) ?? glyphPath
                let paths = flatten(positioned).map { path in
                    path.map { point in CGPoint(x: horizontalOffset + point.x * scale, y: verticalOffset + (ascent - Double(point.y)) * scale) }
                }
                contours.append(contentsOf: paths.filter { $0.count > 1 })
            }
        }
        return contours
    }

    private static func flatten(_ path: CGPath) -> [[CGPoint]] {
        var contours: [[CGPoint]] = []
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                if points.count > 1 { contours.append(points) }
                points = [element.points[0]]; current = element.points[0]
            case .addLineToPoint:
                current = element.points[0]; points.append(current)
            case .addQuadCurveToPoint:
                let start = current, control = element.points[0], end = element.points[1]
                for step in 1...8 {
                    let t = CGFloat(step) / 8, u = 1 - t
                    points.append(CGPoint(x: u*u*start.x + 2*u*t*control.x + t*t*end.x, y: u*u*start.y + 2*u*t*control.y + t*t*end.y))
                }
                current = end
            case .addCurveToPoint:
                let start = current, c1 = element.points[0], c2 = element.points[1], end = element.points[2]
                for step in 1...10 {
                    let t = CGFloat(step) / 10, u = 1 - t
                    points.append(CGPoint(x: u*u*u*start.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x,
                                          y: u*u*u*start.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y))
                }
                current = end
            case .closeSubpath:
                if let first = points.first, points.last != first { points.append(first) }
                if points.count > 1 { contours.append(points) }
                points = []
            @unknown default: break
            }
        }
        if points.count > 1 { contours.append(points) }
        return contours
    }

    private static func hatch(for object: DesignObject, spacing: Double, feed: Double, power: Int) -> [String] {
        var lines: [String] = []
        let maxY = object.y + object.height
        var y = object.y + spacing
        var reverse = false
        while y < maxY {
            let inset: Double
            if object.kind == .circle {
                let ny = (y - object.y - object.height / 2) / (object.height / 2)
                inset = object.width / 2 * (1 - sqrt(max(0, 1 - ny * ny)))
            } else { inset = 0 }
            let left = object.x + inset, right = object.x + object.width - inset
            guard right > left else { y += spacing; continue }
            let startX = reverse ? right : left, endX = reverse ? left : right
            lines += ["M5", "G0 X\(fmt(startX)) Y\(fmt(ray5Workspace - y))", "M4 S0",
                      "G1 X\(fmt(endX)) Y\(fmt(ray5Workspace - y)) F\(fmt(feed)) S\(power)", "M5"]
            reverse.toggle(); y += spacing
        }
        return lines
    }

    private static func hatch(paths: [[CGPoint]], spacing: Double, feed: Double, power: Int) -> [String] {
        let allPoints = paths.flatMap { $0 }
        guard let minY = allPoints.map(\.y).min(), let maxY = allPoints.map(\.y).max() else { return [] }
        var lines: [String] = []
        var y = minY + spacing
        var reverse = false
        while y < maxY {
            var intersections: [Double] = []
            for path in paths where path.count > 1 {
                for (a, b) in zip(path, path.dropFirst()) where (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                    intersections.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                }
            }
            intersections.sort()
            for pairIndex in stride(from: 0, through: max(-1, intersections.count - 2), by: 2) where pairIndex + 1 < intersections.count {
                let left = intersections[pairIndex], right = intersections[pairIndex + 1]
                let startX = reverse ? right : left, endX = reverse ? left : right
                lines += ["M5", "G0 X\(fmt(startX)) Y\(fmt(ray5Workspace - y))", "M4 S0",
                          "G1 X\(fmt(endX)) Y\(fmt(ray5Workspace - y)) F\(fmt(feed)) S\(power)", "M5"]
                reverse.toggle()
            }
            y += spacing
        }
        return lines
    }

    private static func fmt(_ value: Double) -> String { String(format: "%.3f", value) }

    enum GenerationError: LocalizedError {
        case invalidSValue
        case outOfBounds(String)
        case noBurnLayers
        case invalidImage(String)
        var errorDescription: String? {
            switch self {
            case .invalidSValue: "GRBL S-value maximum must be between 1 and 10000."
            case .outOfBounds(let label): "\(label) is outside the 400 × 400 mm Ray5 work area."
            case .noBurnLayers: "Turn Burn on for at least one layer before generating a job."
            case .invalidImage(let label): "\(label) does not contain usable image data. Reimport the image before generating the job."
            }
        }
    }
}
