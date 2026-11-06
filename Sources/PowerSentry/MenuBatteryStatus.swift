import AppKit
import SwiftUI

/// Status-bar battery information. Never display the percentage or wattage
/// outside the battery image itself.
struct MenuBatteryStatus {
    let percentage: Int?

    init(battery: BatterySnapshot?) {
        guard let battery else {
            percentage = nil
            return
        }
        percentage = min(max(Int(battery.percentage.rounded()), 0), 100)
    }

    var percentageText: String {
        percentage.map(String.init) ?? "—"
    }
}

/// Render the complete battery as a SINGLE status-bar image.
///
/// MenuBarExtra's label does not reliably preserve arbitrary SwiftUI shape
/// compositions on every macOS version: the Text may survive while its
/// RoundedRectangle stroke is dropped. A single template NSImage avoids that.
enum MenuBatteryImageRenderer {
    static let width: CGFloat = 35
    static let height: CGFloat = 17
    static let pixelScale = 3

    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(percentage: Int?) -> NSImage {
        let level = percentage.map { min(max($0, 0), 100) }
        let key = NSNumber(value: level ?? -1)
        if let cached = cache.object(forKey: key) { return cached }

        guard let rep = bitmap(percentage: level) else {
            return NSImage(size: NSSize(width: width, height: height))
        }

        let result = NSImage(size: NSSize(width: width, height: height))
        result.addRepresentation(rep)
        result.isTemplate = true  // macOS automatically tints it for light/dark bars.
        cache.setObject(result, forKey: key)
        return result
    }

    static func bitmap(percentage: Int?) -> NSBitmapImageRep? {
        let pxWidth = Int(width) * pixelScale
        let pxHeight = Int(height) * pixelScale

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxWidth,
            pixelsHigh: pxHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        graphics.imageInterpolation = .high
        graphics.shouldAntialias = true
        graphics.cgContext.scaleBy(x: CGFloat(pixelScale), y: CGFloat(pixelScale))

        NSColor.black.set()

        // Leave real pixels for the outer border, including at 100% charge.
        let outer = NSBezierPath(
            roundedRect: NSRect(x: 1, y: 1.65, width: 30, height: 13.7),
            xRadius: 2.6,
            yRadius: 2.6
        )
        outer.lineWidth = 1.35
        outer.stroke()

        // Positive battery terminal at the right of the outline.
        NSBezierPath(
            roundedRect: NSRect(x: 32, y: 6.1, width: 2.1, height: 4.8),
            xRadius: 0.65,
            yRadius: 0.65
        ).fill()

        let text = percentage.map(String.init) ?? "—"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let x = 1 + (30 - size.width) / 2
        let y = 1.65 + (13.7 - size.height) / 2
        attributed.draw(at: NSPoint(x: x, y: y))

        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Pixel-level assertion used by --self-test: a bitmap with text alone must
    /// not pass because the right-side battery terminal would be missing.
    static func hasDrawnOutlineAndTerminal(percentage: Int?) -> Bool {
        guard let rep = bitmap(percentage: percentage) else { return false }
        let scale = CGFloat(pixelScale)

        func anyOpaque(_ logicalRect: NSRect) -> Bool {
            let xRange = Int(logicalRect.minX * scale)..<Int(logicalRect.maxX * scale)
            let yRange = Int(logicalRect.minY * scale)..<Int(logicalRect.maxY * scale)
            for x in xRange where x >= 0 && x < rep.pixelsWide {
                for y in yRange where y >= 0 && y < rep.pixelsHigh {
                    if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                        return true
                    }
                }
            }
            return false
        }

        let topBorder = anyOpaque(NSRect(x: 12, y: 14.3, width: 8, height: 2))
        let bottomBorder = anyOpaque(NSRect(x: 12, y: 1, width: 8, height: 2))
        let leftBorder = anyOpaque(NSRect(x: 0, y: 5, width: 3, height: 7))
        let terminal = anyOpaque(NSRect(x: 32, y: 6, width: 3, height: 5))
        let digits = anyOpaque(NSRect(x: 7, y: 4, width: 20, height: 9))
        return topBorder && bottomBorder && leftBorder && terminal && digits
    }
}

struct MenuBatteryStatusLabel: View {
    let battery: BatterySnapshot?

    var body: some View {
        let status = MenuBatteryStatus(battery: battery)
        Image(nsImage: MenuBatteryImageRenderer.image(percentage: status.percentage))
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: MenuBatteryImageRenderer.width, height: MenuBatteryImageRenderer.height)
            .help("PowerSentry · " + status.percentageText)
            .accessibilityLabel(tr("metric.battery_level") + " " + status.percentageText)
    }
}
