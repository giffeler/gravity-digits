import CoreGraphics
import CoreText
import Foundation
import SpriteKit

final class DigitMask {
    let text: String
    let size: CGSize
    let scale: CGFloat
    let texture: SKTexture

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]

    private init(text: String, size: CGSize, scale: CGFloat, width: Int, height: Int, bytes: [UInt8], image: CGImage) {
        self.text = text
        self.size = size
        self.scale = scale
        self.width = width
        self.height = height
        self.bytes = bytes
        self.texture = SKTexture(cgImage: image)
        self.texture.filteringMode = .linear
    }

    static func make(text: String, size: CGSize, scale: CGFloat = PerformanceConfig.maskScale) -> DigitMask? {
        let pixelWidth = max(2, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(2, Int((size.height * scale).rounded(.up)))
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var rgba = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: &rgba,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.textMatrix = .identity

        let font = fittedFont(for: text, canvas: CGSize(width: pixelWidth, height: pixelHeight))
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return nil
        }
        let line = CTLineCreateWithAttributedString(attributed)

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let lineHeight = ascent + descent + leading

        let x = (CGFloat(pixelWidth) - lineWidth) * 0.5
        let baseline = (CGFloat(pixelHeight) - lineHeight) * 0.5 + descent
        context.textPosition = CGPoint(x: x, y: baseline)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { return nil }

        var alphaBytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
        for y in 0..<pixelHeight {
            let sourceRow = y * bytesPerRow
            let destinationRow = y * pixelWidth
            for x in 0..<pixelWidth {
                alphaBytes[destinationRow + x] = rgba[sourceRow + x * bytesPerPixel + 3]
            }
        }

        return DigitMask(
            text: text,
            size: size,
            scale: scale,
            width: pixelWidth,
            height: pixelHeight,
            bytes: alphaBytes,
            image: image
        )
    }

    func isObstacle(point: CGPoint) -> Bool {
        sample(point: point) > 20
    }

    func approximateNormal(point: CGPoint) -> CGVector {
        let spacing = max(1.0 / scale, 0.5)
        let left = CGFloat(sample(point: CGPoint(x: point.x - spacing, y: point.y))) / 255.0
        let right = CGFloat(sample(point: CGPoint(x: point.x + spacing, y: point.y))) / 255.0
        let down = CGFloat(sample(point: CGPoint(x: point.x, y: point.y - spacing))) / 255.0
        let up = CGFloat(sample(point: CGPoint(x: point.x, y: point.y + spacing))) / 255.0

        let gradient = CGVector(dx: right - left, dy: up - down)
        let outward = CGVector(dx: -gradient.dx, dy: -gradient.dy)
        let length = sqrt(outward.dx * outward.dx + outward.dy * outward.dy)
        guard length > 0.0001 else {
            return fallbackNormal(from: point)
        }

        return CGVector(dx: outward.dx / length, dy: outward.dy / length)
    }

    private func fallbackNormal(from point: CGPoint) -> CGVector {
        var bestVector = CGVector(dx: 0, dy: 1)
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let searchRadius = Int(max(2, 4 * scale))
        let pixel = pixelPoint(for: point)

        for yOffset in -searchRadius...searchRadius {
            for xOffset in -searchRadius...searchRadius {
                let x = pixel.x + xOffset
                let y = pixel.y + yOffset
                guard x >= 0, y >= 0, x < width, y < height else { continue }
                if bytes[y * width + x] <= 20 {
                    let dx = CGFloat(xOffset) / scale
                    let dy = CGFloat(yOffset) / scale
                    let distance = dx * dx + dy * dy
                    if distance > 0, distance < bestDistance {
                        bestDistance = distance
                        let length = sqrt(distance)
                        bestVector = CGVector(dx: dx / length, dy: dy / length)
                    }
                }
            }
        }

        return bestVector
    }

    private func sample(point: CGPoint) -> UInt8 {
        let pixel = pixelPoint(for: point)
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < width, pixel.y < height else { return 0 }
        return bytes[pixel.y * width + pixel.x]
    }

    private func pixelPoint(for point: CGPoint) -> (x: Int, y: Int) {
        let x = Int((point.x * scale).rounded(.down))
        let y = Int((point.y * scale).rounded(.down))
        return (x, y)
    }

    private static func fittedFont(for text: String, canvas: CGSize) -> CTFont {
        let minimumSize: CGFloat = 12
        var low = minimumSize
        var high = min(canvas.height * 0.43, canvas.width * 0.33)
        var best = minimumSize

        for _ in 0..<8 {
            let candidate = (low + high) * 0.5
            let font = makeFont(size: candidate)
            let attributes: [CFString: Any] = [kCTFontAttributeName: font]
            let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
            let line = CTLineCreateWithAttributedString(attributed)
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            if width <= canvas.width * 0.91, ascent + descent + leading <= canvas.height * 0.48 {
                best = candidate
                low = candidate
            } else {
                high = candidate
            }
        }

        return makeFont(size: best)
    }

    private static func makeFont(size: CGFloat) -> CTFont {
        if let fixedPitch = CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil) {
            return fixedPitch
        }

        return CTFontCreateWithName("Menlo-Bold" as CFString, size, nil)
    }
}
