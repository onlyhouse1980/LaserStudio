import Foundation
import SwiftUI

enum SVGImporter {
    private struct RawShape {
        var points: [CGPoint]
        var closed: Bool
        var name: String
    }

    static func load(_ url: URL) throws -> [DesignObject] {
        let svgData = try Data(contentsOf: url)
        let delegate = Parser()
        let parser = XMLParser(data: svgData)
        parser.delegate = delegate
        guard parser.parse() else {
            if let raster = try? ImageImporter.load(svgData: svgData, label: url.deletingPathExtension().lastPathComponent) {
                return [raster]
            }
            throw parser.parserError ?? ImportError.invalidSVG
        }
        if delegate.hasUnsupportedGeometry || delegate.shapes.isEmpty {
            return [try ImageImporter.load(svgData: svgData, label: url.deletingPathExtension().lastPathComponent)]
        }

        let viewBox = delegate.viewBox ?? CGRect(x: 0, y: 0,
                                                 width: delegate.shapes.flatMap(\.points).map(\.x).max() ?? 1,
                                                 height: delegate.shapes.flatMap(\.points).map(\.y).max() ?? 1)
        let scale = min(360 / max(1, viewBox.width), 360 / max(1, viewBox.height))
        let offsetX = (400 - viewBox.width * scale) / 2
        let offsetY = (400 - viewBox.height * scale) / 2
        return delegate.shapes.enumerated().compactMap { index, shape in
            let converted = shape.points.map { CGPoint(x: offsetX + ($0.x - viewBox.minX) * scale,
                                                       y: offsetY + ($0.y - viewBox.minY) * scale) }
            guard let minX = converted.map(\.x).min(), let maxX = converted.map(\.x).max(),
                  let minY = converted.map(\.y).min(), let maxY = converted.map(\.y).max(), converted.count > 1 else { return nil }
            let local = converted.map { CGPoint(x: $0.x - minX, y: $0.y - minY) }
            return DesignObject(kind: .path, x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY),
                                label: shape.name.isEmpty ? "Imported path \(index + 1)" : shape.name,
                                pathPoints: local, pathIsClosed: shape.closed)
        }
    }

    private final class Parser: NSObject, XMLParserDelegate {
        var shapes: [RawShape] = []
        var viewBox: CGRect?
        var hasUnsupportedGeometry = false
        private var transformStack: [[CGAffineTransform]] = [[]]

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
            var transforms = transformStack.last ?? []
            if let value = a["transform"] {
                if let parsed = parseTransforms(value) { transforms.append(contentsOf: parsed) }
                else { hasUnsupportedGeometry = true }
            }
            transformStack.append(transforms)
            switch name.lowercased() {
            case "svg":
                if let value = a["viewBox"], let numbers = parseNumbers(value), numbers.count >= 4 {
                    viewBox = CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
                } else {
                    viewBox = CGRect(x: 0, y: 0, width: number(a["width"], default: 400), height: number(a["height"], default: 400))
                }
            case "title": break
            case "rect":
                let x = number(a["x"]), y = number(a["y"]), w = number(a["width"]), h = number(a["height"])
                add([CGPoint(x: x, y: y), CGPoint(x: x + w, y: y), CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)], closed: true, name: a["id"] ?? "Rectangle")
            case "circle", "ellipse":
                let cx = number(a["cx"]), cy = number(a["cy"])
                let rx = name.lowercased() == "circle" ? number(a["r"]) : number(a["rx"])
                let ry = name.lowercased() == "circle" ? rx : number(a["ry"])
                let points = (0...72).map { i -> CGPoint in
                    let angle = 2 * Double.pi * Double(i) / 72
                    return CGPoint(x: cx + rx * cos(angle), y: cy + ry * sin(angle))
                }
                add(points, closed: true, name: a["id"] ?? "Ellipse")
            case "line":
                add([CGPoint(x: number(a["x1"]), y: number(a["y1"])), CGPoint(x: number(a["x2"]), y: number(a["y2"]))], closed: false, name: a["id"] ?? "Line")
            case "polygon", "polyline":
                let points = parseNumbers(a["points"] ?? "")
                if let points, points.count >= 4 {
                    let coords = stride(from: 0, to: points.count - 1, by: 2).map { CGPoint(x: points[$0], y: points[$0 + 1]) }
                    add(coords, closed: name.lowercased() == "polygon", name: a["id"] ?? "Path")
                }
            case "path":
                if let d = a["d"], let contours = parsePath(d) {
                    for (index, contour) in contours.enumerated() { add(contour.points, closed: contour.closed, name: a["id"] ?? "Path \(index + 1)") }
                } else { hasUnsupportedGeometry = true }
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName qName: String?) {
            if transformStack.count > 1 { transformStack.removeLast() }
        }

        private func add(_ points: [CGPoint], closed: Bool, name: String) {
            guard points.count > 1 else { return }
            let transformed = (transformStack.last ?? []).reversed().reduce(points) { currentPoints, transform in
                currentPoints.map { $0.applying(transform) }
            }
            shapes.append(RawShape(points: transformed, closed: closed, name: name))
        }

        private func parseTransforms(_ source: String) -> [CGAffineTransform]? {
            let pattern = "([A-Za-z]+)\\s*\\(([^)]*)\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let nsSource = source as NSString
            let matches = regex.matches(in: source, range: NSRange(location: 0, length: nsSource.length))
            guard !matches.isEmpty else { return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] : nil }
            var parsed: [CGAffineTransform] = []
            var previousEnd = 0
            for match in matches {
                let gap = nsSource.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
                guard gap.allSatisfy({ $0.isWhitespace || $0 == "," }),
                      let nameRange = Range(match.range(at: 1), in: source),
                      let valueRange = Range(match.range(at: 2), in: source),
                      let values = parseNumbers(String(source[valueRange])) else { return nil }
                let name = source[nameRange].lowercased()
                let transform: CGAffineTransform
                switch name {
                case "matrix" where values.count == 6:
                    transform = CGAffineTransform(a: values[0], b: values[1], c: values[2], d: values[3], tx: values[4], ty: values[5])
                case "translate" where (1...2).contains(values.count):
                    transform = CGAffineTransform(translationX: values[0], y: values.count == 2 ? values[1] : 0)
                case "scale" where (1...2).contains(values.count):
                    transform = CGAffineTransform(scaleX: values[0], y: values.count == 2 ? values[1] : values[0])
                case "rotate" where values.count == 1 || values.count == 3:
                    let angle = values[0] * .pi / 180
                    if values.count == 3 {
                        let center = CGPoint(x: values[1], y: values[2])
                        parsed.append(CGAffineTransform(translationX: center.x, y: center.y))
                        parsed.append(CGAffineTransform(rotationAngle: angle))
                        parsed.append(CGAffineTransform(translationX: -center.x, y: -center.y))
                        previousEnd = NSMaxRange(match.range)
                        continue
                    }
                    transform = CGAffineTransform(rotationAngle: angle)
                case "skewx" where values.count == 1:
                    transform = CGAffineTransform(a: 1, b: 0, c: tan(values[0] * .pi / 180), d: 1, tx: 0, ty: 0)
                case "skewy" where values.count == 1:
                    transform = CGAffineTransform(a: 1, b: tan(values[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
                default: return nil
                }
                parsed.append(transform)
                previousEnd = NSMaxRange(match.range)
            }
            let trailing = nsSource.substring(from: previousEnd)
            guard trailing.allSatisfy({ $0.isWhitespace || $0 == "," }) else { return nil }
            return parsed
        }

        private func number(_ value: String?, default fallback: Double = 0) -> Double {
            guard let value, let match = parseNumbers(value)?.first else { return fallback }
            return match
        }

        private func parseNumbers(_ value: String) -> [Double]? {
            let pattern = "[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(value.startIndex..., in: value)
            return regex.matches(in: value, range: range).compactMap { match in
                guard let r = Range(match.range, in: value) else { return nil }
                return Double(value[r])
            }
        }

        private func parsePath(_ source: String) -> [(points: [CGPoint], closed: Bool)]? {
            let pattern = "[A-Za-z]|[-+]?(?:[0-9]*\\.)?[0-9]+(?:[eE][-+]?[0-9]+)?"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))
            let tokens = matches.compactMap { Range($0.range, in: source).map { String(source[$0]) } }
            var paths: [(points: [CGPoint], closed: Bool)] = []
            var points: [CGPoint] = [], current = CGPoint.zero, start = CGPoint.zero
            var command: Character?, i = 0
            var previousSegment: Character?
            var previousCubicControl: CGPoint?
            var previousQuadraticControl: CGPoint?
            func val() -> Double? { guard i < tokens.count, let value = Double(tokens[i]) else { return nil }; i += 1; return value }
            func finish(_ close: Bool = false) {
                if close, let first = points.first, points.last != first { points.append(first) }
                if points.count > 1 { paths.append((points, close)) }
                points = []
            }
            while i < tokens.count {
                if let first = tokens[i].first, first.isLetter { command = first; i += 1 }
                guard let cmd = command else { return nil }
                let relative = cmd.isLowercase
                switch cmd.uppercased() {
                case "M", "L":
                    guard let x = val(), let y = val() else { return nil }
                    let point = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    if cmd.uppercased() == "M" { finish(); start = point; command = relative ? "l" : "L" }
                    current = point; points.append(point)
                    previousSegment = cmd.uppercased().first
                case "H":
                    guard let x = val() else { return nil }
                    current.x = relative ? current.x + x : x; points.append(current)
                    previousSegment = "H"
                case "V":
                    guard let y = val() else { return nil }
                    current.y = relative ? current.y + y : y; points.append(current)
                    previousSegment = "V"
                case "Q":
                    guard let x1 = val(), let y1 = val(), let x = val(), let y = val() else { return nil }
                    let p0 = current, c = CGPoint(x: relative ? current.x + x1 : x1, y: relative ? current.y + y1 : y1)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    for step in 1...10 { let t = Double(step) / 10, u = 1 - t; points.append(CGPoint(x: u*u*p0.x + 2*u*t*c.x + t*t*end.x, y: u*u*p0.y + 2*u*t*c.y + t*t*end.y)) }
                    current = end; previousQuadraticControl = c; previousSegment = "Q"
                case "T":
                    guard let x = val(), let y = val() else { return nil }
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    let control = (previousSegment == "Q" || previousSegment == "T")
                        ? CGPoint(x: 2 * current.x - (previousQuadraticControl?.x ?? current.x), y: 2 * current.y - (previousQuadraticControl?.y ?? current.y))
                        : current
                    let p0 = current
                    for step in 1...10 { let t = Double(step) / 10, u = 1 - t; points.append(CGPoint(x: u*u*p0.x + 2*u*t*control.x + t*t*end.x, y: u*u*p0.y + 2*u*t*control.y + t*t*end.y)) }
                    current = end; previousQuadraticControl = control; previousSegment = "T"
                case "C":
                    guard let x1 = val(), let y1 = val(), let x2 = val(), let y2 = val(), let x = val(), let y = val() else { return nil }
                    let p0 = current, c1 = CGPoint(x: relative ? current.x + x1 : x1, y: relative ? current.y + y1 : y1)
                    let c2 = CGPoint(x: relative ? current.x + x2 : x2, y: relative ? current.y + y2 : y2)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    for step in 1...12 { let t = Double(step) / 12, u = 1 - t; points.append(CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x, y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)) }
                    current = end; previousCubicControl = c2; previousSegment = "C"
                case "S":
                    guard let x2 = val(), let y2 = val(), let x = val(), let y = val() else { return nil }
                    let c1 = (previousSegment == "C" || previousSegment == "S")
                        ? CGPoint(x: 2 * current.x - (previousCubicControl?.x ?? current.x), y: 2 * current.y - (previousCubicControl?.y ?? current.y))
                        : current
                    let c2 = CGPoint(x: relative ? current.x + x2 : x2, y: relative ? current.y + y2 : y2)
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    let p0 = current
                    for step in 1...12 { let t = Double(step) / 12, u = 1 - t; points.append(CGPoint(x: u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*end.x, y: u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*end.y)) }
                    current = end; previousCubicControl = c2; previousSegment = "S"
                case "A":
                    guard let rx = val(), let ry = val(), let rotation = val(), let largeArc = val(), let sweep = val(), let x = val(), let y = val(),
                          (largeArc == 0 || largeArc == 1), (sweep == 0 || sweep == 1) else { return nil }
                    let end = CGPoint(x: relative ? current.x + x : x, y: relative ? current.y + y : y)
                    points.append(contentsOf: arcPoints(from: current, to: end, radiusX: rx, radiusY: ry,
                                                        rotation: rotation, largeArc: largeArc == 1, sweep: sweep == 1))
                    current = end; previousSegment = "A"
                case "Z":
                    current = start; finish(true); command = nil; previousSegment = "Z"
                default: return nil
                }
            }
            finish()
            return paths.isEmpty ? nil : paths
        }

        private func arcPoints(from start: CGPoint, to end: CGPoint, radiusX: Double, radiusY: Double,
                               rotation: Double, largeArc: Bool, sweep: Bool) -> [CGPoint] {
            let x1 = Double(start.x), y1 = Double(start.y), x2 = Double(end.x), y2 = Double(end.y)
            var rx = abs(radiusX), ry = abs(radiusY)
            guard rx > 0, ry > 0, start != end else { return [end] }
            let phi = rotation * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)
            let dx = (x1 - x2) / 2, dy = (y1 - y2) / 2
            let xPrime = cosPhi * dx + sinPhi * dy
            let yPrime = -sinPhi * dx + cosPhi * dy
            let radiusScale = xPrime * xPrime / (rx * rx) + yPrime * yPrime / (ry * ry)
            if radiusScale > 1 {
                let factor = sqrt(radiusScale)
                rx *= factor; ry *= factor
            }
            let rx2 = rx * rx, ry2 = ry * ry
            let numerator = max(0, rx2 * ry2 - rx2 * yPrime * yPrime - ry2 * xPrime * xPrime)
            let denominator = rx2 * yPrime * yPrime + ry2 * xPrime * xPrime
            let sign = largeArc == sweep ? -1.0 : 1.0
            let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
            let centerXPrime = coefficient * rx * yPrime / ry
            let centerYPrime = coefficient * -ry * xPrime / rx
            let centerX = cosPhi * centerXPrime - sinPhi * centerYPrime + (x1 + x2) / 2
            let centerY = sinPhi * centerXPrime + cosPhi * centerYPrime + (y1 + y2) / 2
            let u = ((xPrime - centerXPrime) / rx, (yPrime - centerYPrime) / ry)
            let v = ((-xPrime - centerXPrime) / rx, (-yPrime - centerYPrime) / ry)
            let startAngle = atan2(u.1, u.0)
            var deltaAngle = atan2(u.0 * v.1 - u.1 * v.0, u.0 * v.0 + u.1 * v.1)
            if !sweep && deltaAngle > 0 { deltaAngle -= 2 * .pi }
            if sweep && deltaAngle < 0 { deltaAngle += 2 * .pi }
            let segmentCount = min(180, max(2, Int(ceil(abs(deltaAngle) / (.pi / 18)))) )
            return (1...segmentCount).map { index in
                let angle = startAngle + deltaAngle * Double(index) / Double(segmentCount)
                let x = centerX + cosPhi * rx * cos(angle) - sinPhi * ry * sin(angle)
                let y = centerY + sinPhi * rx * cos(angle) + cosPhi * ry * sin(angle)
                return index == segmentCount ? end : CGPoint(x: x, y: y)
            }
        }
    }

    private enum ImportError: LocalizedError {
        case invalidSVG
        var errorDescription: String? {
            switch self {
            case .invalidSVG: "The SVG file is invalid or contains unsupported path commands."
            }
        }
    }
}
