import ShelfCore
import SwiftUI

/// Live download and upload rates, each with its own auto-scaling history.
struct NetworkWidget: View {
    let context: WidgetContext
    @Environment(AppModel.self) private var model

    private var tier: InfoTier { InfoTier(context.size) }

    var body: some View {
        let stats = model.system
        let down = Channel(label: "Download", symbol: "arrow.down", history: stats.download, color: Theme.ember)
        let up = Channel(label: "Upload", symbol: "arrow.up", history: stats.upload, color: Theme.brass)
        WidgetCard {
            if tier == .small {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Eyebrow(text: "Network")
                    ChannelView(channel: down, compact: true)
                    ChannelView(channel: up, compact: true)
                }
            } else {
                HStack(spacing: Theme.Space.l) {
                    ChannelView(channel: down, compact: false)
                    ChannelView(channel: up, compact: false)
                }
            }
        }
        .watchesSystemStats()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network")
        .accessibilityValue("Download \(ByteRate.format(down.current)), upload \(ByteRate.format(up.current))")
    }
}

private struct Channel {
    let label: String
    let symbol: String
    let history: SampleHistory
    let color: Color

    var current: Double { history.values.last ?? 0 }
    var peak: Double { history.values.max() ?? 0 }
    /// 16 KB/s floor keeps background chatter from filling the chart.
    var ceiling: Double { InfoSparkline.ceiling(for: history.values, floor: 16_000) }
}

private struct ChannelView: View {
    let channel: Channel
    let compact: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let parts = InfoFormat.rateParts(channel.current)
        VStack(alignment: .leading, spacing: compact ? 3 : 4) {
            if !compact { Eyebrow(text: channel.label) }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: channel.symbol)
                    .font(.system(size: compact ? 10 : 12, weight: .heavy))
                    .foregroundStyle(channel.color)
                Text(parts.value)
                    .font(Theme.Typeface.numeral(compact ? 17 : 24))

                Text(parts.unit)
                    .font(Theme.Typeface.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .lineLimit(1)
            InfoSparkline(history: channel.history, color: channel.color, ceiling: channel.ceiling)
                .frame(maxHeight: .infinity)
            if !compact {
                Text("Peak \(ByteRate.format(channel.peak))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
