import AppKit
import XCTest
@testable import LaserStudio

final class ImageImporterTests: XCTestCase {
    func testImportsPNGJPEGBMPAsImageLayers() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.setColor(.black, atX: 0, y: 0)
        bitmap.setColor(.white, atX: 1, y: 0)
        bitmap.setColor(.gray, atX: 0, y: 1)
        bitmap.setColor(.clear, atX: 1, y: 1)

        let formats: [(NSBitmapImageRep.FileType, String)] = [(.png, "png"), (.jpeg, "jpg"), (.bmp, "bmp")]
        for (format, extensionName) in formats {
            guard let encoded = bitmap.representation(using: format, properties: [:]) else {
                XCTFail("Could not encode test fixture as \(extensionName)")
                continue
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).appendingPathExtension(extensionName)
            defer { try? FileManager.default.removeItem(at: url) }
            try encoded.write(to: url)

            let object = try ImageImporter.load(url)
            XCTAssertEqual(object.kind, .image)
            XCTAssertEqual(object.imagePixelWidth, 2)
            XCTAssertEqual(object.imagePixelHeight, 2)
            XCTAssertEqual(object.imagePixels?.count, 4)
            XCTAssertNotNil(object.imageData)
            XCTAssertTrue(object.variablePower)
            XCTAssertLessThan(object.minimumSpeed, object.maximumSpeed)
        }
    }

    func testLightBurnImageDitherModesAndConvertToBitmap() throws {
        let rect = DesignObject(
            kind: .rectangle,
            x: 50, y: 50, width: 40, height: 30,
            label: "Box", color: .red
        )
        let bitmapObj = try XCTUnwrap(ImageImporter.convertToBitmap(rect, dpi: 96.0))
        XCTAssertEqual(bitmapObj.kind, .image)
        XCTAssertGreaterThan(bitmapObj.imagePixelWidth, 20)
        XCTAssertGreaterThan(bitmapObj.imagePixelHeight, 20)

        for mode in ImageDitherMode.allCases {
            var copy = bitmapObj
            copy.imageDitherMode = mode
            let processed = ImageImporter.processedGrayscale(for: copy)
            XCTAssertEqual(processed.count, copy.imagePixelWidth * copy.imagePixelHeight, "Dither mode \(mode.rawValue) failed")
        }
    }

    func testLightBurnTraceImageOptionsAndCompoundPath() {
        let width = 32
        let height = 32
        var pixels = [UInt8](repeating: 255, count: width * height)
        for y in 6..<26 {
            for x in 6..<26 {
                let isInnerHole = (12..<20).contains(x) && (12..<20).contains(y)
                pixels[y * width + x] = isInnerHole ? 255 : 0
            }
        }
        let img = DesignObject(
            kind: .image,
            x: 20, y: 20, width: 40, height: 40,
            label: "Ring.png", color: .blue,
            imagePixels: Data(pixels), imagePixelWidth: width, imagePixelHeight: height
        )
        var options = ImageTraceOptions(cutoff: 0, threshold: 128, minimumRegion: 4, smoothness: 0.8)
        let contours = ImageTracer.trace(image: img, options: options)
        XCTAssertGreaterThanOrEqual(contours.count, 2, "Should trace outer square and inner hole")

        let compoundLayers = ImageTracer.makePathLayers(from: img, contours: contours, combineIntoCompoundPath: true)
        XCTAssertEqual(compoundLayers.count, 1, "Compound path mode should combine outer contour and inner hole into 1 layer")
        XCTAssertGreaterThanOrEqual(compoundLayers[0].pathSubpaths.count, 2)

        options.sketchTrace = true
        let sketchContours = ImageTracer.trace(image: img, options: options)
        XCTAssertFalse(sketchContours.isEmpty, "Sketch trace should detect edges")
    }

    func testLightBurnPolygonOffsetAndBooleanOperations() {
        let ws = CGSize(width: 400, height: 400)
        let poly = DesignObject(
            kind: .polygon,
            x: 100, y: 100, width: 60, height: 60,
            label: "Hexagon", color: .orange,
            cornerRadius: 4, polygonSides: 6
        )
        let pathObj = ShapeGeometry.convertToPath(poly)
        XCTAssertEqual(pathObj.kind, .path)
        XCTAssertFalse(pathObj.pathPoints.isEmpty)

        let offsetObj = ShapeGeometry.offsetObject(
            from: [poly], distance: 5.0,
            direction: .outward, cornerStyle: .round,
            workspace: ws
        )
        XCTAssertNotNil(offsetObj)
        XCTAssertGreaterThan(offsetObj?.width ?? 0, poly.width)

        let boxA = DesignObject(kind: .rectangle, x: 80, y: 80, width: 50, height: 50, label: "A", color: .red)
        let boxB = DesignObject(kind: .rectangle, x: 105, y: 80, width: 50, height: 50, label: "B", color: .blue)
        for op in BooleanOperationKind.allCases {
            let result = ShapeGeometry.booleanOperation(op, objects: [boxA, boxB], workspace: ws)
            XCTAssertNotNil(result, "Boolean \(op.rawValue) should produce a valid vector shape")
        }
    }

    func testLightBurnLayerPropertiesInGCodeGenerator() throws {
        let shape = DesignObject(
            kind: .polygon,
            x: 40, y: 40, width: 30, height: 30,
            label: "MultiPassHex", color: .red,
            power: 80, minPower: 20, speed: 1200,
            layerMode: .fillAndLine, passCount: 2,
            crossHatch: true, constantPower: true, airAssist: true,
            tabsEnabled: true, tabSize: 2.0, tabCount: 4,
            polygonSides: 6
        )
        let toolFrame = DesignObject(
            kind: .rectangle,
            x: 10, y: 10, width: 100, height: 100,
            label: "T1 Guide", color: .orange,
            isToolLayer: true
        )
        let lines = try GCodeGenerator.make(
            objects: [shape, toolFrame],
            material: "Birch",
            sMax: 1000,
            kerf: 0.5,
            machine: .ray5
        )
        XCTAssertTrue(lines.contains("M8"), "Air assist M8 should be emitted")
        XCTAssertTrue(lines.contains(where: { $0.hasPrefix("M3 S") }), "Constant power mode should emit M3")
        let m5Count = lines.filter { $0 == "M5" }.count
        XCTAssertGreaterThanOrEqual(m5Count, 3, "Multiple passes and Fill+Line should emit multiple laser strokes")
    }

    func testLightBurnCompoundPathGroupUngroupAndBreakApart() {
        let rectA = DesignObject(kind: .rectangle, x: 20, y: 20, width: 30, height: 30, label: "A", color: .red)
        let rectB = DesignObject(kind: .rectangle, x: 80, y: 20, width: 30, height: 30, label: "B", color: .red)

        guard let compound = ShapeGeometry.combineIntoCompoundPath([rectA, rectB]) else {
            XCTFail("Expected compound path from two rectangles")
            return
        }
        XCTAssertEqual(compound.resolvedSubpaths.count, 2)

        let ungrouped = ShapeGeometry.breakApartSubpaths(compound)
        XCTAssertEqual(ungrouped.count, 2, "Ungrouping a compound vector path should break it into individual subpaths")
        XCTAssertEqual(ungrouped[0].width, 30, accuracy: 0.01)
        XCTAssertEqual(ungrouped[1].width, 30, accuracy: 0.01)

        let segments = ShapeGeometry.breakApartSegments(ungrouped[0])
        XCTAssertEqual(segments.count, 4, "Breaking apart a rectangle path should produce 4 individual line segments")
    }

    func testTextFontModifiersProduceUnderlineAndStrikethroughContours() throws {
        let plain = DesignObject(
            kind: .text,
            x: 50,
            y: 50,
            width: 120,
            height: 28,
            label: "Laser",
            fontBold: true,
            fontItalic: true
        )
        let plainSubpaths = ShapeGeometry.localSubpaths(for: plain)
        XCTAssertFalse(plainSubpaths.isEmpty)

        var decorated = plain
        decorated.fontUnderline = true
        decorated.fontStrikethrough = true
        let decoratedSubpaths = ShapeGeometry.localSubpaths(for: decorated)
        XCTAssertEqual(decoratedSubpaths.count, plainSubpaths.count + 2, "Underline and Strikethrough should add 2 vector bar contours")

        let gcodePlain = try GCodeGenerator.make(objects: [plain], material: "Custom", sMax: 1000, kerf: 0.5, machine: .ray5)
        let gcodeDecorated = try GCodeGenerator.make(objects: [decorated], material: "Custom", sMax: 1000, kerf: 0.5, machine: .ray5)
        XCTAssertGreaterThan(gcodeDecorated.count, gcodePlain.count, "Underline and Strikethrough should emit additional G-code strokes")
    }
}
