import CoreGraphics
import CoreText
import Foundation
import SpriteKit

final class DigitMask {
    private struct PixelBounds {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int

        var width: Int { maxX - minX + 1 }
        var height: Int { maxY - minY + 1 }
    }

    let text: String
    let size: CGSize
    let scale: CGFloat
    let texture: SKTexture

    private static let obstacleThreshold: UInt8 = 20

    private let width: Int
    private let height: Int
    private let bytes: [UInt8]
    private let normalX: [Int8]
    private let normalY: [Int8]
    private let normalBounds: PixelBounds?
    private let potentialContact: [UInt8]
    private(set) var obstacleBounds: CGRect?

    private init(
        text: String,
        size: CGSize,
        scale: CGFloat,
        width: Int,
        height: Int,
        bytes: [UInt8],
        normalX: [Int8],
        normalY: [Int8],
        normalBounds: PixelBounds?,
        potentialContact: [UInt8],
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
        self.normalBounds = normalBounds
        self.potentialContact = potentialContact
        self.obstacleBounds = obstacleBounds
        self.texture = SKTexture(cgImage: image)
        self.texture.filteringMode = .linear
    }

    static func make(text: String, size: CGSize, scale: CGFloat = PerformanceConfig.maskScale) -> DigitMask? {
        let pixelWidth = max(2, Int((size.width * scale).rounded(.up)))
        let pixelHeight = max(2, Int((size.height * scale).rounded(.up)))
        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        let rgba = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: pixelHeight * bytesPerRow)
        rgba.initialize(repeating: 0)
        defer { rgba.deallocate() }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(
            data: rgba.baseAddress,
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

        let alphaBytes = sceneAlphaBytes(
            from: rgba.baseAddress,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            bytesPerRow: bytesPerRow
        )
        var minObstacleX = pixelWidth
        var minObstacleY = pixelHeight
        var maxObstacleX = -1
        var maxObstacleY = -1

        for y in 0..<pixelHeight {
            for x in 0..<pixelWidth {
                let alpha = alphaBytes[y * pixelWidth + x]
                if alpha > obstacleThreshold {
                    minObstacleX = min(minObstacleX, x)
                    minObstacleY = min(minObstacleY, y)
                    maxObstacleX = max(maxObstacleX, x)
                    maxObstacleY = max(maxObstacleY, y)
                }
            }
        }

        let normalBounds: PixelBounds?
        let obstacleBounds: CGRect?
        if maxObstacleX >= minObstacleX, maxObstacleY >= minObstacleY {
            normalBounds = PixelBounds(
                minX: minObstacleX,
                minY: minObstacleY,
                maxX: maxObstacleX,
                maxY: maxObstacleY
            )
            obstacleBounds = CGRect(
                x: CGFloat(minObstacleX) / scale,
                y: CGFloat(minObstacleY) / scale,
                width: CGFloat(maxObstacleX - minObstacleX + 1) / scale,
                height: CGFloat(maxObstacleY - minObstacleY + 1) / scale
            )
        } else {
            normalBounds = nil
            obstacleBounds = nil
        }

        let normals = makeNormalField(
            bytes: alphaBytes,
            width: pixelWidth,
            height: pixelHeight,
            scale: scale,
            bounds: normalBounds
        )
        let potentialContact = makePotentialContactMap(
            bytes: alphaBytes,
            width: pixelWidth,
            height: pixelHeight,
            scale: scale
        )

        return DigitMask(
            text: text,
            size: size,
            scale: scale,
            width: pixelWidth,
            height: pixelHeight,
            bytes: alphaBytes,
            normalX: normals.x,
            normalY: normals.y,
            normalBounds: normalBounds,
            potentialContact: potentialContact,
            obstacleBounds: obstacleBounds,
            image: image
        )
    }

    static func sceneAlphaBytes(
        from rgba: UnsafePointer<UInt8>?,
        pixelWidth: Int,
        pixelHeight: Int,
        bytesPerRow: Int
    ) -> [UInt8] {
        guard let rgba else { return [] }
        let bytesPerPixel = 4
        var alphaBytes = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
        alphaBytes.withUnsafeMutableBufferPointer { alphaBuffer in
            guard let alphaBase = alphaBuffer.baseAddress else { return }
            for y in 0..<pixelHeight {
                let sourceRow = (pixelHeight - 1 - y) * bytesPerRow
                let destinationRow = y * pixelWidth
                for x in 0..<pixelWidth {
                    alphaBase[destinationRow + x] = rgba[sourceRow + x * bytesPerPixel + 3]
                }
            }
        }
        return alphaBytes
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

    func contactPoint(around center: CGPoint, radius: CGFloat) -> CGPoint? {
        guard mightIntersectObstacle(center: center, radius: radius) else { return nil }

        return potentialContact.withUnsafeBufferPointer { contactBuffer in
            bytes.withUnsafeBufferPointer { byteBuffer in
                guard let contactBase = contactBuffer.baseAddress,
                      let byteBase = byteBuffer.baseAddress else {
                    return nil
                }

                let paddedRadius = radius + (1.0 / scale)
                let centerX = center.x * scale
                let centerY = center.y * scale
                let centerPixelX = Int(centerX.rounded(.down))
                let centerPixelY = Int(centerY.rounded(.down))

                if centerPixelX >= 0,
                   centerPixelY >= 0,
                   centerPixelX < width,
                   centerPixelY < height,
                   contactBase[centerPixelY * width + centerPixelX] == 0 {
                    return nil
                }

                let radiusSquared = paddedRadius * paddedRadius * scale * scale
                let pixelRadius = Int((paddedRadius * scale).rounded(.up))
                let minX = max(0, centerPixelX - pixelRadius)
                let maxX = min(width - 1, centerPixelX + pixelRadius)
                let minY = max(0, centerPixelY - pixelRadius)
                let maxY = min(height - 1, centerPixelY + pixelRadius)

                guard minX <= maxX, minY <= maxY else { return nil }

                var bestPoint: CGPoint?
                var bestDistance = CGFloat.greatestFiniteMagnitude

                for y in minY...maxY {
                    for x in minX...maxX {
                        guard byteBase[y * width + x] > Self.obstacleThreshold else { continue }

                        let dx = CGFloat(x) + 0.5 - centerX
                        let dy = CGFloat(y) + 0.5 - centerY
                        let distance = dx * dx + dy * dy
                        if distance <= radiusSquared, distance < bestDistance {
                            bestDistance = distance
                            bestPoint = CGPoint(x: (CGFloat(x) + 0.5) / scale, y: (CGFloat(y) + 0.5) / scale)
                        }
                    }
                }

                return bestPoint
            }
        }
    }

    func approximateNormal(point: CGPoint) -> CGVector {
        let pixel = pixelPoint(for: point)
        guard let normalBounds,
              pixel.x >= normalBounds.minX,
              pixel.y >= normalBounds.minY,
              pixel.x <= normalBounds.maxX,
              pixel.y <= normalBounds.maxY else {
            return CGVector(dx: 0, dy: 1)
        }

        let index = (pixel.y - normalBounds.minY) * normalBounds.width + pixel.x - normalBounds.minX
        return CGVector(dx: CGFloat(normalX[index]) / 127.0, dy: CGFloat(normalY[index]) / 127.0)
    }

    private func sample(point: CGPoint) -> UInt8 {
        let pixel = pixelPoint(for: point)
        guard pixel.x >= 0, pixel.y >= 0, pixel.x < width, pixel.y < height else { return 0 }
        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return 0 }
            return baseAddress[pixel.y * width + pixel.x]
        }
    }

    private func pixelPoint(for point: CGPoint) -> (x: Int, y: Int) {
        let x = Int((point.x * scale).rounded(.down))
        let y = Int((point.y * scale).rounded(.down))
        return (x, y)
    }

    private static func makeNormalField(
        bytes: [UInt8],
        width: Int,
        height: Int,
        scale: CGFloat,
        bounds: PixelBounds?
    ) -> (x: [Int8], y: [Int8]) {
        guard let bounds else { return ([], []) }
        var normalX = [Int8](repeating: 0, count: bounds.width * bounds.height)
        var normalY = [Int8](repeating: 127, count: bounds.width * bounds.height)
        let contactRadius = (PerformanceConfig.maximumParticleRadius + (1.0 / scale)) * scale
        let normalBandRadius = Int((contactRadius * sqrt(2.0)).rounded(.up)) + 1
        let surfaceDistance = makeSurfaceDistance(bytes: bytes, width: width, height: height)

        for y in bounds.minY...bounds.maxY {
            for x in bounds.minX...bounds.maxX {
                let sourceIndex = y * width + x
                guard bytes[sourceIndex] > obstacleThreshold,
                      surfaceDistance[sourceIndex] <= normalBandRadius else {
                    continue
                }
                let normalIndex = (y - bounds.minY) * bounds.width + x - bounds.minX

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
                    normalX[normalIndex] = quantizedNormal(outwardX / length)
                    normalY[normalIndex] = quantizedNormal(outwardY / length)
                } else {
                    let fallback = fallbackNormal(
                        fromX: x,
                        y: y,
                        bytes: bytes,
                        width: width,
                        height: height,
                        scale: scale,
                        searchRadius: normalBandRadius
                    )
                    normalX[normalIndex] = quantizedNormal(fallback.dx)
                    normalY[normalIndex] = quantizedNormal(fallback.dy)
                }
            }
        }

        return (normalX, normalY)
    }

    private static func quantizedNormal(_ component: CGFloat) -> Int8 {
        let scaled = (max(-1, min(1, component)) * 127.0).rounded()
        return Int8(scaled)
    }

    private static func makeSurfaceDistance(bytes: [UInt8], width: Int, height: Int) -> [Int] {
        let unreachable = width + height + 1
        var distance = [Int](repeating: unreachable, count: width * height)

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                if bytes[index] <= obstacleThreshold {
                    distance[index] = 0
                    continue
                }

                let fromLeft = x == 0 ? 1 : distance[index - 1] + 1
                let fromBelow = y == 0 ? 1 : distance[index - width] + 1
                distance[index] = min(fromLeft, fromBelow)
            }
        }

        for y in stride(from: height - 1, through: 0, by: -1) {
            for x in stride(from: width - 1, through: 0, by: -1) {
                let index = y * width + x
                guard bytes[index] > obstacleThreshold else { continue }
                let fromRight = x == width - 1 ? 1 : distance[index + 1] + 1
                let fromAbove = y == height - 1 ? 1 : distance[index + width] + 1
                distance[index] = min(distance[index], fromRight, fromAbove)
            }
        }

        return distance
    }

    private static func alpha(atX x: Int, y: Int, bytes: [UInt8], width: Int, height: Int) -> UInt8 {
        guard x >= 0, y >= 0, x < width, y < height else { return 0 }
        return bytes[y * width + x]
    }

    private static func makePotentialContactMap(bytes: [UInt8], width: Int, height: Int, scale: CGFloat) -> [UInt8] {
        let maxPaddedRadius = (PerformanceConfig.maximumParticleRadius + (1.0 / scale)) * scale
        let pixelRadius = Int((maxPaddedRadius + 1.0).rounded(.up))
        var horizontal = [UInt8](repeating: 0, count: width * height)

        for y in 0..<height {
            let row = y * width
            var obstacleCount = 0
            for x in 0...min(width - 1, pixelRadius) where bytes[row + x] > obstacleThreshold {
                obstacleCount += 1
            }

            for x in 0..<width {
                horizontal[row + x] = obstacleCount > 0 ? 1 : 0

                let leavingX = x - pixelRadius
                if leavingX >= 0, bytes[row + leavingX] > obstacleThreshold {
                    obstacleCount -= 1
                }
                let enteringX = x + pixelRadius + 1
                if enteringX < width, bytes[row + enteringX] > obstacleThreshold {
                    obstacleCount += 1
                }
            }
        }

        var map = [UInt8](repeating: 0, count: width * height)
        for x in 0..<width {
            var contactCount = 0
            for y in 0...min(height - 1, pixelRadius) where horizontal[y * width + x] != 0 {
                contactCount += 1
            }

            for y in 0..<height {
                map[y * width + x] = contactCount > 0 ? 1 : 0

                let leavingY = y - pixelRadius
                if leavingY >= 0, horizontal[leavingY * width + x] != 0 {
                    contactCount -= 1
                }
                let enteringY = y + pixelRadius + 1
                if enteringY < height, horizontal[enteringY * width + x] != 0 {
                    contactCount += 1
                }
            }
        }

        return map
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
