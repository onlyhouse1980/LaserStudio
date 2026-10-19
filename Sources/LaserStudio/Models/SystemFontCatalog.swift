import AppKit
import CoreText

struct TextFitMetrics {
    let font: CTFont
    let lineWidth: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let scale: CGFloat

    var fittedFontSize: CGFloat { CTFontGetSize(font) * scale }
}

enum SystemFontCatalog {
    static let families: [String] = {
        let installed = NSFontManager.shared.availableFontFamilies
        return Array(Set(installed + ["Helvetica"]))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }()

    static func font(family: String, size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let baseFont = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size)
            ?? NSFont(name: family, size: size)
            ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        return traits.isEmpty ? baseFont : NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
    }

    static func fittedTextMetrics(label: String, family: String, width: Double, height: Double,
                                  bold: Bool = false, italic: Bool = false,
                                  baseFontSize: CGFloat = 100) -> TextFitMetrics {
        let selectedFont = font(family: family, size: baseFontSize, bold: bold, italic: italic)
        let font = CTFontCreateWithName(selectedFont.fontName as CFString, baseFontSize, nil)
        let attributed = NSAttributedString(string: label, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let scale = min(CGFloat(width) / max(1, lineWidth), CGFloat(height) / max(1, ascent + descent))
        return TextFitMetrics(font: font, lineWidth: lineWidth, ascent: ascent, descent: descent, scale: scale)
    }
}
