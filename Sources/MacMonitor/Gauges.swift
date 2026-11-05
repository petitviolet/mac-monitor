import MacMonitorCore
import SwiftUI

struct RingGauge: View {
    let title: String
    /// nilは計測中を表す。
    let fraction: Double?
    var diameter: CGFloat = 110
    var lineWidth: CGFloat = 12
    var valueFont: Font = .title2

    private var valueText: String {
        fraction.map { Formatting.percent(fraction: $0) } ?? DetailText.measuring
    }

    var body: some View {
        ZStack {
            Circle().stroke(VizPalette.track, lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(VizPalette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(valueText)
                    .font(fraction == nil ? .callout : valueFont)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText)
    }
}

/// 列幅を固定して、コア数が多いときは折り返す。
struct CoreBars: View {
    private static let columnWidth: CGFloat = 28
    private static let barWidth: CGFloat = 12
    private static let barHeight: CGFloat = 56
    private static let cornerRadius: CGFloat = 3

    let usages: [Double]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.columnWidth), spacing: 2)], spacing: 8) {
            ForEach(Array(usages.enumerated()), id: \.offset) { index, usage in
                VStack(spacing: 2) {
                    ZStack(alignment: .bottom) {
                        UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius)
                            .fill(VizPalette.track)
                        UnevenRoundedRectangle(topLeadingRadius: Self.cornerRadius, topTrailingRadius: Self.cornerRadius)
                            .fill(VizPalette.accent)
                            .frame(height: Self.barHeight * min(max(usage, 0), 1))
                    }
                    .frame(width: Self.barWidth, height: Self.barHeight)
                    Text(Formatting.percent(fraction: usage))
                        .font(.caption2)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("コア\(index + 1)")
                .accessibilityValue(Formatting.percent(fraction: usage))
            }
        }
    }
}

struct MeterBar: View {
    private static let height: CGFloat = 12

    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(VizPalette.track)
                Capsule()
                    .fill(VizPalette.accent)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: Self.height)
    }
}

struct StackedBarSegment: Identifiable {
    let name: String
    let bytes: UInt64
    let color: Color

    var id: String { name }
}

struct StackedBar: View {
    private static let height: CGFloat = 20
    private static let gap: CGFloat = 2
    private static let cornerRadius: CGFloat = 4

    let segments: [StackedBarSegment]

    private var visible: [StackedBarSegment] { segments.filter { $0.bytes > 0 } }

    var body: some View {
        GeometryReader { proxy in
            let total = visible.reduce(0.0) { $0 + Double($1.bytes) }
            let drawable = proxy.size.width - Self.gap * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: Self.gap) {
                ForEach(visible) { segment in
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(segment.color)
                        .frame(width: total > 0 ? drawable * Double(segment.bytes) / total : 0)
                }
            }
        }
        .frame(height: Self.height)
        .accessibilityHidden(true)
    }
}

struct StackedBarLegend: View {
    private static let swatchSize: CGFloat = 10

    let segments: [StackedBarSegment]
    let totalBytes: UInt64

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            ForEach(segments) { segment in
                GridRow {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(segment.color)
                        .frame(width: Self.swatchSize, height: Self.swatchSize)
                    Text(segment.name)
                    Text(Formatting.bytes(segment.bytes))
                        .monospacedDigit()
                        .gridColumnAlignment(.trailing)
                    Text(Formatting.percent(fraction: totalBytes == 0 ? 0 : Double(segment.bytes) / Double(totalBytes)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                }
            }
        }
    }
}
