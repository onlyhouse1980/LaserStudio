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
}
