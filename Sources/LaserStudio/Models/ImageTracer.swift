import Foundation
import CoreGraphics

struct ImageTraceOptions: Equatable {
    var cutoff: Double = 0
    var threshold: Double = 128
    var inverted: Bool = false
    var sketchTrace: Bool = false
    var minimumRegion: Double = 2
    var smoothness: Double = 1.0
    var simplifyTolerance: Double = 0.35
    var fadeImage: Bool = true
    var showPoints: Bool = false
    var deleteImageAfterTrace: Bool = false
    var combineIntoCompoundPath: Bool = true
    var cropNormalizedRect: CGRect? = nil
}

enum ImageTracer {
    // Keep tracing responsive for large raster imports and avoid creating
    // unmanageable numbers of vector layers from highly detailed images.
    private static let maximumTraceDimension = 1_024
    static let maximumContourCount = 2_500

    static func trace(image: DesignObject, options: ImageTraceOptions) -> [[CGPoint]] {
        guard let pixels = image.imagePixels,
              image.imagePixelWidth > 0, image.imagePixelHeight > 0,
              pixels.count >= image.imagePixelWidth * image.imagePixelHeight else { return [] }

        let width = min(maximumTraceDimension, image.imagePixelWidth)
        let height = min(maximumTraceDimension, image.imagePixelHeight)
        let source = [UInt8](pixels)

        let minXCrop = options.cropNormalizedRect.map { max(0, Int((Double($0.minX) * Double(width)).rounded(.down))) } ?? 0
        let maxXCrop = options.cropNormalizedRect.map { min(width, Int((Double($0.maxX) * Double(width)).rounded(.up))) } ?? width
        let minYCrop = options.cropNormalizedRect.map { max(0, Int((Double($0.minY) * Double(height)).rounded(.down))) } ?? 0
        let maxYCrop = options.cropNormalizedRect.map { min(height, Int((Double($0.maxY) * Double(height)).rounded(.up))) } ?? height

        var mask = [UInt8](repeating: 0, count: width * height)
        let lowCutoff = min(options.cutoff, options.threshold)
        let highThreshold = max(options.cutoff, options.threshold)

        if options.sketchTrace {
            // LightBurn Sketch Trace: Sobel gradient magnitude edge detector
            var downsampled = [Double](repeating: 255, count: width * height)
            for y in 0..<height {
                let sourceY = min(image.imagePixelHeight - 1, y * image.imagePixelHeight / height)
                for x in 0..<width {
                    let sourceX = min(image.imagePixelWidth - 1, x * image.imagePixelWidth / width)
                    downsampled[y * width + x] = Double(source[sourceY * image.imagePixelWidth + sourceX])
                }
            }
            let edgeThreshold = max(8.0, 255.0 - highThreshold)
            for y in max(1, minYCrop)..<min(height - 1, maxYCrop) {
                for x in max(1, minXCrop)..<min(width - 1, maxXCrop) {
                    let tl = downsampled[(y - 1) * width + (x - 1)]
                    let tc = downsampled[(y - 1) * width + x]
                    let tr = downsampled[(y - 1) * width + (x + 1)]
                    let ml = downsampled[y * width + (x - 1)]
                    let mr = downsampled[y * width + (x + 1)]
                    let bl = downsampled[(y + 1) * width + (x - 1)]
                    let bc = downsampled[(y + 1) * width + x]
                    let br = downsampled[(y + 1) * width + (x + 1)]
                    let gx = -tl + tr - 2 * ml + 2 * mr - bl + br
                    let gy = -tl - 2 * tc - tr + bl + 2 * bc + br
                    let mag = min(255.0, hypot(gx, gy) / 4.0)
                    let matches = mag >= edgeThreshold
                    if options.inverted ? !matches : matches {
                        mask[y * width + x] = 1
                    }
                }
            }
        } else {
            for y in minYCrop..<maxYCrop {
                let sourceY = min(image.imagePixelHeight - 1, y * image.imagePixelHeight / height)
                for x in minXCrop..<maxXCrop {
                    let sourceX = min(image.imagePixelWidth - 1, x * image.imagePixelWidth / width)
                    let value = Double(source[sourceY * image.imagePixelWidth + sourceX])
                    let gray = options.inverted ? 255 - value : value
                    if gray >= lowCutoff && gray <= highThreshold {
                        mask[y * width + x] = 1
                    }
                }
            }
        }

        filterSmallRegions(&mask, width: width, height: height, minimumSize: max(1, Int(options.minimumRegion.rounded())))
        let contours = boundaries(
            mask: mask,
            width: width,
            height: height,
            smoothness: options.smoothness,
            tolerance: options.simplifyTolerance
        )
        let scaleX = Double(image.imagePixelWidth) / Double(width)
        let scaleY = Double(image.imagePixelHeight) / Double(height)
        return contours.map { contour in
            contour.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
        }
    }

    static func makePathLayers(from image: DesignObject, contours: [[CGPoint]], combineIntoCompoundPath: Bool = true) -> [DesignObject] {
        guard image.imagePixelWidth > 0, image.imagePixelHeight > 0 else { return [] }
        let mmPerPixelX = image.width / Double(image.imagePixelWidth)
        let mmPerPixelY = image.height / Double(image.imagePixelHeight)
        let scaledContours: [[CGPoint]] = contours.compactMap { contour in
            let pts = contour.map { CGPoint(x: $0.x * mmPerPixelX, y: $0.y * mmPerPixelY) }
            return pts.count > 3 ? pts : nil
        }
        guard !scaledContours.isEmpty else { return [] }

        if combineIntoCompoundPath {
            let allPts = scaledContours.flatMap { $0 }
            guard let minX = allPts.map(\.x).min(), let maxX = allPts.map(\.x).max(),
                  let minY = allPts.map(\.y).min(), let maxY = allPts.map(\.y).max() else { return [] }
            let subpaths = scaledContours.map { contour -> PathSubpath in
                var local = contour.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
                if let first = local.first, local.last != first { local.append(first) }
                return PathSubpath(points: local, isClosed: true)
            }
            let swatch = LightBurnPalette.layers[0] // Default 00 Black Line layer like LightBurn
            return [
                DesignObject(
                    kind: .path,
                    x: image.x + minX,
                    y: image.y + minY,
                    width: max(0.1, maxX - minX),
                    height: max(0.1, maxY - minY),
                    label: "\(image.label) Trace",
                    rotation: image.rotation,
                    color: swatch.color,
                    power: image.power,
                    speed: image.maximumSpeed,
                    burnEnabled: image.burnEnabled,
                    layerMode: .line,
                    pathSubpaths: subpaths
                )
            ]
        }

        let groupID = scaledContours.count > 1 ? UUID() : nil
        return scaledContours.enumerated().compactMap { index, points in
            guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
            let local = points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
            return DesignObject(
                kind: .path,
                x: image.x + minX,
                y: image.y + minY,
                width: max(0.1, maxX - minX),
                height: max(0.1, maxY - minY),
                label: "\(image.label) trace \(index + 1)",
                color: LightBurnPalette.layers[0].color,
                power: image.power,
                speed: image.maximumSpeed,
                burnEnabled: image.burnEnabled,
                layerMode: .line,
                pathPoints: local,
                pathIsClosed: true,
                groupID: groupID
            )
        }
    }

    private struct Edge {
        let start: Int
        let end: Int
        let direction: Int
    }

    private static func filterSmallRegions(_ mask: inout [UInt8], width: Int, height: Int, minimumSize: Int) {
        guard minimumSize > 1 else { return }
        var visited = [UInt8](repeating: 0, count: mask.count)
        for origin in mask.indices where mask[origin] == 1 && visited[origin] == 0 {
            var component = [origin]
            visited[origin] = 1
            var cursor = 0
            while cursor < component.count {
                let index = component[cursor]
                cursor += 1
                let x = index % width, y = index / width
                if x > 0 { append(index - 1, mask: mask, visited: &visited, component: &component) }
                if x + 1 < width { append(index + 1, mask: mask, visited: &visited, component: &component) }
                if y > 0 { append(index - width, mask: mask, visited: &visited, component: &component) }
                if y + 1 < height { append(index + width, mask: mask, visited: &visited, component: &component) }
            }
            if component.count < minimumSize {
                for index in component { mask[index] = 0 }
            }
        }
    }

    private static func append(_ index: Int, mask: [UInt8], visited: inout [UInt8], component: inout [Int]) {
        guard mask[index] == 1, visited[index] == 0 else { return }
        visited[index] = 1
        component.append(index)
    }

    private static func boundaries(mask: [UInt8], width: Int, height: Int, smoothness: Double, tolerance: Double) -> [[CGPoint]] {
        let vertexWidth = width + 1
        func vertex(_ x: Int, _ y: Int) -> Int { y * vertexWidth + x }
        func isOn(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && x < width && y >= 0 && y < height && mask[y * width + x] == 1
        }

        var edges: [Edge] = []
        var outgoing: [Int: [Int]] = [:]
        func addEdge(_ start: Int, _ end: Int, _ direction: Int) {
            let index = edges.count
            edges.append(Edge(start: start, end: end, direction: direction))
            outgoing[start, default: []].append(index)
        }
        for y in 0..<height {
            for x in 0..<width where isOn(x, y) {
                if !isOn(x, y - 1) { addEdge(vertex(x, y), vertex(x + 1, y), 0) }
                if !isOn(x + 1, y) { addEdge(vertex(x + 1, y), vertex(x + 1, y + 1), 1) }
                if !isOn(x, y + 1) { addEdge(vertex(x + 1, y + 1), vertex(x, y + 1), 2) }
                if !isOn(x - 1, y) { addEdge(vertex(x, y + 1), vertex(x, y), 3) }
            }
        }

        var used = [UInt8](repeating: 0, count: edges.count)
        var result: [[CGPoint]] = []
        for firstEdge in edges.indices where used[firstEdge] == 0 && result.count < maximumContourCount {
            let startVertex = edges[firstEdge].start
            var points = [CGPoint(x: startVertex % vertexWidth, y: startVertex / vertexWidth)]
            var edgeIndex = firstEdge
            var closed = false
            for _ in 0...edges.count {
                guard used[edgeIndex] == 0 else { break }
                used[edgeIndex] = 1
                let edge = edges[edgeIndex]
                let currentVertex = edge.end
                if currentVertex == startVertex { closed = true; break }
                points.append(CGPoint(x: currentVertex % vertexWidth, y: currentVertex / vertexWidth))
                let candidates = (outgoing[currentVertex] ?? []).filter { used[$0] == 0 }
                guard let next = candidates.min(by: { turnPriority(from: edge.direction, to: edges[$0].direction) < turnPriority(from: edge.direction, to: edges[$1].direction) }) else { break }
                edgeIndex = next
            }
            guard closed, points.count >= 4 else { continue }
            points.append(points[0])
            var processed = tolerance > 0 ? simplify(points, tolerance: tolerance) : points
            if smoothness > 0.05 && processed.count >= 4 {
                processed = smoothClosedContour(processed, factor: min(2.0, max(0, smoothness)))
            }
            if processed.count >= 4 { result.append(processed) }
        }
        return result
    }

    private static func smoothClosedContour(_ points: [CGPoint], factor: Double) -> [CGPoint] {
        var ring = points
        if let first = ring.first, let last = ring.last, hypot(first.x - last.x, first.y - last.y) < 0.001 {
            ring.removeLast()
        }
        guard ring.count >= 3 else { return points }
        let passes = factor > 1.1 ? 2 : 1
        let weight = CGFloat(min(0.35, max(0.05, factor * 0.22)))
        for _ in 0..<passes {
            guard ring.count >= 3, ring.count < 800 else { break }
            var nextRing: [CGPoint] = []
            nextRing.reserveCapacity(ring.count * 2)
            for i in 0..<ring.count {
                let p0 = ring[i]
                let p1 = ring[(i + 1) % ring.count]
                let q = CGPoint(x: (1 - weight) * p0.x + weight * p1.x, y: (1 - weight) * p0.y + weight * p1.y)
                let r = CGPoint(x: weight * p0.x + (1 - weight) * p1.x, y: weight * p0.y + (1 - weight) * p1.y)
                nextRing.append(q)
                nextRing.append(r)
            }
            ring = nextRing
        }
        if let first = ring.first { ring.append(first) }
        return ring
    }

    private static func turnPriority(from: Int, to: Int) -> Int {
        switch (to - from + 4) % 4 {
        case 1: return 0 // Keep diagonally touching regions on separate outlines.
        case 0: return 1
        case 3: return 2
        default: return 3
        }
    }

    private static func simplify(_ points: [CGPoint], tolerance: Double) -> [CGPoint] {
        guard points.count > 4 else { return points }
        let first = points[0], last = points[points.count - 1]
        var greatestDistance = 0.0
        var split = 0
        for index in 1..<(points.count - 1) {
            let distance = distanceFromLine(points[index], first, last)
            if distance > greatestDistance { greatestDistance = distance; split = index }
        }
        guard greatestDistance > tolerance, split > 0 else { return [first, last] }
        let left = simplify(Array(points[0...split]), tolerance: tolerance)
        let right = simplify(Array(points[split...]), tolerance: tolerance)
        return left.dropLast() + right
    }

    private static func distanceFromLine(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> Double {
        let dx = Double(end.x - start.x), dy = Double(end.y - start.y)
        let length = hypot(dx, dy)
        guard length > 0 else { return hypot(Double(point.x - start.x), Double(point.y - start.y)) }
        return abs(dy * Double(point.x - start.x) - dx * Double(point.y - start.y)) / length
    }
}
