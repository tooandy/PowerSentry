import SwiftUI

/// A compact status-bar presentation. Percentages are shown inside the icon,
/// with no extra menu-bar text or wattage.
struct MenuBatteryStatus {
    let percentage: Int?

    init(battery: BatterySnapshot?) {
        guard let battery else {
            percentage = nil
            return
        }
        percentage = Int(battery.percentage.rounded()).clamped(to: 0...100)
    }

    var percentageText: String {
        percentage.map { "\($0)%" } ?? "—"
    }
}

/// A scalable, crisp, monochrome battery outline with the percentage drawn INSIDE.
/// No asset images, emoji or SF Symbols are used for the battery itself.
struct MenuBatteryGlyph: View {
    let percentage: Int?

    // Slightly taller and wider than the system battery SF Symbol, but still
    // contained in the macOS menu bar's normal 22-point vertical layout.
    static let bodyWidth: CGFloat = 36
    static let bodyHeight: CGFloat = 17
    static let tipWidth: CGFloat = 2.5

    var body: some View {
        HStack(alignment: .center, spacing: 1) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(.primary, lineWidth: 1.5)
                    .frame(width: Self.bodyWidth, height: Self.bodyHeight)

                Text(percentage.map { "\($0)%" } ?? "—")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .foregroundStyle(.primary)
                    .frame(width: Self.bodyWidth - 4, height: Self.bodyHeight)
            }
            .frame(width: Self.bodyWidth, height: Self.bodyHeight)

            RoundedRectangle(cornerRadius: 0.8)
                .fill(.primary)
                .frame(width: Self.tipWidth, height: 7)
        }
        .frame(height: 20)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("metric.battery_level") + " " + (percentage.map { "\($0)%" } ?? "—"))
    }
}

struct MenuBatteryStatusLabel: View {
    let battery: BatterySnapshot?

    var body: some View {
        let status = MenuBatteryStatus(battery: battery)
        MenuBatteryGlyph(percentage: status.percentage)
            .foregroundStyle(.primary)
            .help("PowerSentry · " + status.percentageText)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
