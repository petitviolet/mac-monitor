import MacMonitorCore
import SwiftUI

struct ResourcesView: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    CPUCard(usage: model.snapshot?.cpu)
                    MemoryCard(usage: model.snapshot?.memory)
                }
                HStack(alignment: .top, spacing: 12) {
                    DiskCard(usage: model.snapshot?.disk)
                    NetworkCard(rate: model.snapshot?.network)
                }
            }
            .padding(12)
        }
    }
}

private struct Card<Content: View>: View {
    private static var cornerRadius: CGFloat { 10 }

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(VizPalette.surface, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.separator))
    }
}

private struct CPUCard: View {
    let usage: CPUUsage?

    var body: some View {
        Card(title: "CPU") {
            HStack(alignment: .top, spacing: 12) {
                RingGauge(title: "全体", fraction: usage?.overall)
                VStack(alignment: .leading, spacing: 6) {
                    Text("コア別").font(.subheadline).foregroundStyle(.secondary)
                    if let usage {
                        CoreBars(usages: usage.perCore)
                    } else {
                        Text(DetailText.measuring).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct MemoryCard: View {
    let usage: MemoryUsage?

    var body: some View {
        Card(title: "メモリ") {
            if let usage {
                let segments = Self.segments(usage)
                HStack(alignment: .top, spacing: 16) {
                    RingGauge(title: "使用中", fraction: usage.usedFraction)
                    VStack(alignment: .leading, spacing: 8) {
                        StackedBar(segments: segments)
                        StackedBarLegend(segments: segments, totalBytes: usage.totalBytes)
                        Text("合計\(Formatting.bytes(usage.totalBytes))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("メモリの情報を取得できませんでした").foregroundStyle(.secondary)
            }
        }
    }

    private static func segments(_ usage: MemoryUsage) -> [StackedBarSegment] {
        [
            StackedBarSegment(name: "アプリ", bytes: usage.appBytes, color: VizPalette.memoryApp),
            StackedBarSegment(name: "確保済み(wired)", bytes: usage.wiredBytes, color: VizPalette.memoryWired),
            StackedBarSegment(name: "圧縮", bytes: usage.compressedBytes, color: VizPalette.memoryCompressed),
            StackedBarSegment(name: "空き(キャッシュ含む)", bytes: usage.freeBytes, color: VizPalette.memoryFree)
        ]
    }
}

private struct DiskCard: View {
    let usage: DiskUsage?

    var body: some View {
        Card(title: "ディスク(ルートボリューム)") {
            if let usage {
                HStack(alignment: .firstTextBaseline) {
                    Text(Formatting.percent(fraction: usage.usedFraction))
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("使用中").foregroundStyle(.secondary)
                }
                MeterBar(fraction: usage.usedFraction)
                Text("空き\(Formatting.bytes(usage.availableBytes)) / 合計\(Formatting.bytes(usage.totalBytes))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            } else {
                Text("ディスクの情報を取得できませんでした").foregroundStyle(.secondary)
            }
        }
    }
}

private struct NetworkCard: View {
    let rate: NetworkRate?

    var body: some View {
        Card(title: "ネットワーク(トンネルと仮想を除く合計)") {
            HStack(spacing: 24) {
                tile(title: "受信", value: rate.map { Formatting.rate($0.receivedBytesPerSecond) })
                tile(title: "送信", value: rate.map { Formatting.rate($0.sentBytesPerSecond) })
            }
        }
    }

    private func tile(title: String, value: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? DetailText.measuring)
                .font(.title2)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
