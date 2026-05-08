import CoreGraphics
import CoreText
import Foundation
import SpriteKit

final class DigitMask {
    let text: String
    let size: CGSize
    let scale: CGFloat
    let texture: SKTexture

    private static let obstacleThreshold: UInt8 = 20

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]
    private let normalX: [Float]
    private let normalY: [Float]
    private let obstacleBounds: CGRect?

    private init(
        text: String,
        size: CGSize,
        scale: CGFloat,
        width: Int,
        height: Int,
        bytes: [UInt8],
        normalX: [Float],
        normalY: [Float],
        obstacleBounds: CGRect?,
        image: CGImage
    ) {
        self.text = text
        self.size = size
        self.scale = scale
        self.width = width
        self.height = height
        self.bytes = bytes
        self.normalX = normalX
        self.normalY = normalY
        self.obstacleBounds = obstacleBounds
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
        var minObstacleX = pixelWidth
        var minObstacleY = pixelHeight
        var maxObstacleX = -1
        var maxObstacleY = -1

        for y in 0..<pixelHeight {
            let sourceRow = y * bytesPerRow
            let destinationRow = y * pixelWidth
            for x in 0..<pixelWidth {
                let alpha = rgba[sourceRow + x * bytesPerPixel + 3]
                alphaBytes[destinationRow + x] = alpha
                if alpha > obstacleThreshold {
                    minObstacleX = min(minObstacleX, x)
                    minObstacleY = min(minObstacleY, y)
                    maxObstacleX = max(maxObstacleX, x)
                    maxObstacleY = max(maxObstacleY, y)
                }
            }
        }

        let obstacleBounds: CGRect?
        if maxObstacleX >= minObstacleX, maxObstacleY >= minObstacleY {
            obstacleBounds = CGRect(
                x: CGFloat(minObstacleX) / scale,
                y: CGFloat(minObstacleY) / scale,
                width: CGFloat(maxObstacleX - minObstacleX + 1) / scale,
                height: CGFloat(maxObstacleY - minObstacleY + 1) / scale
            )
        } else {
            obstacleBounds = nil
        }

        let normals = makeNormalField(bytes: alphaBytes, width: pixelWidth, height: pixelHeight, scale: scale)

        return DigitMask(
            text: text,
            size: size,
            scale: scale,
            width: pixelWidth,
            height: pixelHeight,
            bytes: alphaBytes,
            normalX: normals.x,
            normalY: normals.y,
            obstacleBounds: obstacleBounds,
            image: image
        )
    }

    func mightIntersectObstacle(center: CGPoint, radius: CGFloat) -> Bool {
        guard let obstacleBounds else { return false }
        let margin = max(radius, 1.0) + (1.0 / scale)
        return obstacleBounds.insetBy(dx: -margin, dy: -margin).contains(center)
    }

    func mightIntersectObstacle(from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        guard let obstacleBounds else { return false }
        let margin = max(radius, 1.0) + (1.0 / scale)
        let minX = min(start.x, end.x) - margin
        let minY = min(start.y, end.y) - margin
        let maxX = max(start.x, end.x) + margin
        let maxY = max(start.y, end.y) + margin
        let sweptBounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return sweptBounds.intersects(obstacleBounds)
    }

    func isObstacle(point: CGPoint) -> Bool {
        sample(point: point) > Self.obstacleThreshold
    }

    func approximateNormal(point: CGPoint) -> CGVector {
        let pixel = pixelPoint(for: point)
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < width, pixel.y < height else {
            return CGVector(dx: 0, dy: 1)
        }

        let index = pixel.y * width + pixel.x
        return CGVector(dx: CGFloat(normalX[index]), dy: CGFloat(normalY[index]))
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

    private static func makeNormalField(bytes: [UInt8], width: Int, height: Int, scale: CGFloat) -> (x: [Float], y: [Float]) {
        var normalX = [Float](repeating: 0, count: width * height)
        var normalY = [Float](repeating: 1, count: width * height)
        let fallbackSearchRadius = Int(max(2, 4 * scale))

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard bytes[index] > obstacleThreshold else { continue }

                let left = CGFloat(alpha(atX: x - 1, y: y, bytes: bytes, width: width, height: height)) / 255.0
                let right = CGFloat(alpha(atX: x + 1, y: y, bytes: bytes, width: width, height: height)) / 255.0
                let down = CGFloat(alpha(atX: x, y: y - 1, bytes: bytes, width: width, height: height)) / 255.0
                let up = CGFloat(alpha(atX: x, y: y + 1, bytes: bytes, width: width, height: height)) / 255.0
                let gradientX = right - left
                let gradientY = up - down
                let outwardX = -gradientX
                let outwardY = -gradientY
                let length = sqrt(outwardX * outwardX + outwardY * outwardY)

                if length > 0.0001 {
                    normalX[index] = Float(outwardX / length)
                    normalY[index] = Float(outwardY / length)
                } else {
                    let fallback = fallbackNormal(
                        fromX: x,
                        y: y,
                        bytes: bytes,
                        width: width,
                        height: height,
                        scale: scale,
                        searchRadius: fallbackSearchRadius
                    )
                    normalX[index] = Float(fallback.dx)
                    normalY[index] = Float(fallback.dy)
                }
            }
        }

        return (normalX, normalY)
    }

    private static func alpha(atX x: Int, y: Int, bytes: [UInt8], width: Int, height: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return bytes[y * width + x]
    }

    private static func fallbackNormal(
        fromX pixelX: Int,
        y pixelY: Int,
        bytes: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat,
        searchRadius: Int
    ) -> CGVector {
        var bestVector = CGVector(dx: 0, dy: 1)
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for yOffset in -searchRadius...searchRadius {
            for xOffset in -searchRadius...searchRadius {
                let x = pixelX + xOffset
                let y = pixelY + yOffset
                guard x >= 0, y >= 0, x < width, y < height else { continue }
                if bytes[y * width + x] <= obstacleThreshold {
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
