import AppKit
import SwiftUI

/// Status-bar battery information. Never display the percentage or wattage
/// outside the battery image itself.
struct MenuBatteryStatus {
    let percentage: Int?
    let showsPowerBolt: Bool

    init(battery: BatterySnapshot?) {
        guard let battery else {
            percentage = nil
            showsPowerBolt = false
            return
        }
        percentage = min(max(Int(battery.percentage.rounded()), 0), 100)
        // AppleSmartBattery reports IsCharging=false at 100%, even with the
        // charger connected. Follow ExternalConnected to keep the power icon
        // visible for fully charged Macs while they remain plugged in.
        showsPowerBolt = battery.externalPower
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
    // Smaller than the previous 35×17 pt icon. When connected to external
    // power, reserve a little extra width for the lightning bolt.
    static let width: CGFloat = 29
    static let pluggedWidth: CGFloat = 32
    static let height: CGFloat = 15
    static func width(showBolt: Bool) -> CGFloat {
        showBolt ? pluggedWidth : width
    }
    static let pixelScale = 3

    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(percentage: Int?, showBolt: Bool = false) -> NSImage {
        let level = percentage.map { min(max($0, 0), 100) }
        // Plugged-in and unplugged bitmaps must not share a cached image.
        let key = NSNumber(value: (level ?? -1) * 2 + (showBolt ? 1 : 0))
        if let cached = cache.object(forKey: key) { return cached }

        let imageWidth = width(showBolt: showBolt)
        guard let rep = bitmap(percentage: level, showBolt: showBolt) else {
            return NSImage(size: NSSize(width: imageWidth, height: height))
        }

        let result = NSImage(size: NSSize(width: imageWidth, height: height))
        result.addRepresentation(rep)
        result.isTemplate = true  // macOS automatically tints it for light/dark bars.
        cache.setObject(result, forKey: key)
        return result
    }

    static func bitmap(percentage: Int?, showBolt: Bool = false) -> NSBitmapImageRep? {
        let pxWidth = Int(width(showBolt: showBolt)) * pixelScale
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
            roundedRect: NSRect(x: 0.9, y: 1.5, width: 24.4, height: 12),
            xRadius: 2.1,
            yRadius: 2.1
        )
        outer.lineWidth = 1.15
        outer.stroke()

        // Positive battery terminal at the right of the outline.
        NSBezierPath(
            roundedRect: NSRect(x: 26.2, y: 5.35, width: 1.6, height: 4.3),
            xRadius: 0.6,
            yRadius: 0.6
        ).fill()

        if showBolt {
            // Separate, recognisable lightning symbol. It is part of the
            // same raster image and only appears for ExternalConnected=true.
            let bolt = NSBezierPath()
            bolt.move(to: NSPoint(x: 30.8, y: 12.6))
            bolt.line(to: NSPoint(x: 28.3, y: 7.8))
            bolt.line(to: NSPoint(x: 30.1, y: 7.8))
            bolt.line(to: NSPoint(x: 28.8, y: 2.6))
            bolt.line(to: NSPoint(x: 31.8, y: 8.8))
            bolt.line(to: NSPoint(x: 30.4, y: 8.8))
            bolt.close()
            bolt.fill()
        }

        let text = percentage.map(String.init) ?? "—"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.1, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let size = attributed.size()
        let x = 0.9 + (24.4 - size.width) / 2
        let y = 1.5 + (12 - size.height) / 2
        attributed.draw(at: NSPoint(x: x, y: y))

        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Pixel-level assertion used by --self-test: a bitmap with text alone must
    /// not pass because the right-side battery terminal would be missing.
    private static func hasInk(in rect: NSRect, in rep: NSBitmapImageRep) -> Bool {
        let scale = CGFloat(pixelScale)
        let xRange = Int(rect.minX * scale)..<Int(rect.maxX * scale)
        let yRange = Int(rect.minY * scale)..<Int(rect.maxY * scale)
        for x in xRange where x >= 0 && x < rep.pixelsWide {
            for y in yRange where y >= 0 && y < rep.pixelsHigh {
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
                    return true
                }
            }
        }
        return false
    }

    static func hasDrawnOutlineAndTerminal(percentage: Int?, showBolt: Bool = false) -> Bool {
        guard let rep = bitmap(percentage: percentage, showBolt: showBolt) else { return false }
        let topBorder = hasInk(in: NSRect(x: 10, y: 12, width: 6, height: 3), in: rep)
        let bottomBorder = hasInk(in: NSRect(x: 10, y: 0.5, width: 6, height: 2), in: rep)
        let leftBorder = hasInk(in: NSRect(x: 0, y: 5, width: 2.5, height: 5), in: rep)
        let terminal = hasInk(in: NSRect(x: 26, y: 5, width: 2.5, height: 5), in: rep)
        let digits = hasInk(in: NSRect(x: 5, y: 3.5, width: 19, height: 8), in: rep)
        return topBorder && bottomBorder && leftBorder && terminal && digits
    }

    static func hasDrawnChargingBolt(percentage: Int?, showBolt: Bool) -> Bool {
        guard let rep = bitmap(percentage: percentage, showBolt: showBolt) else { return false }
        return hasInk(in: NSRect(x: 28.3, y: 2, width: 3.7, height: 11), in: rep)
    }
}

struct MenuBatteryStatusLabel: View {
    let battery: BatterySnapshot?

    var body: some View {
        let status = MenuBatteryStatus(battery: battery)
        Image(nsImage: MenuBatteryImageRenderer.image(
            percentage: status.percentage,
            showBolt: status.showsPowerBolt
        ))
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: MenuBatteryImageRenderer.width(showBolt: status.showsPowerBolt),
                   height: MenuBatteryImageRenderer.height)
            .help("PowerSentry · " + status.percentageText +
                  (status.showsPowerBolt ? " · " + tr("detail.external_power") : ""))
            .accessibilityLabel(tr("metric.battery_level") + " " + status.percentageText +
                                (status.showsPowerBolt ? " · " + tr("detail.external_power") : ""))
    }
}
