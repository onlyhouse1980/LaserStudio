import Foundation
import CoreGraphics

struct ImageTraceOptions: Equatable {
    var threshold: Double = 128
    var inverted: Bool = false
    var minimumRegion: Double = 2
    var simplifyTolerance: Double = 0.35
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
        var mask = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let sourceY = min(image.imagePixelHeight - 1, y * image.imagePixelHeight / height)
            for x in 0..<width {
                let sourceX = min(image.imagePixelWidth - 1, x * image.imagePixelWidth / width)
                let value = Double(source[sourceY * image.imagePixelWidth + sourceX])
                let gray = options.inverted ? 255 - value : value
                if gray <= options.threshold { mask[y * width + x] = 1 }
            }
        }
        filterSmallRegions(&mask, width: width, height: height, minimumSize: max(1, Int(options.minimumRegion.rounded())))
        let contours = boundaries(mask: mask, width: width, height: height, tolerance: options.simplifyTolerance)
        let scaleX = Double(image.imagePixelWidth) / Double(width)
        let scaleY = Double(image.imagePixelHeight) / Double(height)
        return contours.map { contour in
            // Keep the image's top-left pixel origin unchanged. The preview,
            // canvas, and generated paths all use this same coordinate order.
            contour.map { CGPoint(x: $0.x * scaleX, y: $0.y * scaleY) }
        }
    }

    static func makePathLayers(from image: DesignObject, contours: [[CGPoint]]) -> [DesignObject] {
        guard image.imagePixelWidth > 0, image.imagePixelHeight > 0 else { return [] }
        let mmPerPixelX = image.width / Double(image.imagePixelWidth)
        let mmPerPixelY = image.height / Double(image.imagePixelHeight)
        return contours.enumerated().compactMap { index, contour in
            let points = contour.map { CGPoint(x: $0.x * mmPerPixelX, y: $0.y * mmPerPixelY) }
            guard points.count > 3,
                  let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
                  let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
            let local = points.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
            return DesignObject(kind: .path, x: image.x + minX, y: image.y + minY,
                                width: max(0.1, maxX - minX), height: max(0.1, maxY - minY),
                                label: "\(image.label) trace \(index + 1)", color: .green,
                                power: image.power, speed: image.maximumSpeed,
                                burnEnabled: image.burnEnabled, layerMode: .line,
                                pathPoints: local, pathIsClosed: true)
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

    private static func boundaries(mask: [UInt8], width: Int, height: Int, tolerance: Double) -> [[CGPoint]] {
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
            let simplified = tolerance > 0 ? simplify(points, tolerance: tolerance) : points
            if simplified.count >= 4 { result.append(simplified) }
        }
        return result
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
