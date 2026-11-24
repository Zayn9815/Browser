import SwiftUI

public struct FloatingMediaPillView: View {
    private let item: InterceptedMediaItem
    private let onPlay: () -> Void
    private let onDownload: () -> Void
    @State private var hapticCounter = 0

    public init(
        item: InterceptedMediaItem,
        onPlay: @escaping () -> Void,
        onDownload: @escaping () -> Void
    ) {
        self.item = item
        self.onPlay = onPlay
        self.onDownload = onDownload
    }

    public var body: some View {
        if !item.isDRMProtected {
            // Strictly no SwiftUI Menu inside GlassEffectContainer
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        hapticCounter += 1
                        onPlay()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                            Text("Play")
                                .font(.subheadline.weight(.semibold))
                            if let height = item.videoHeight, height > 0 {
                                Text("\(height)p")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)

                    Button {
                        hapticCounter += 1
                        onDownload()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.subheadline.weight(.bold))
                            Text(item.containerHint == .m3u8 ? "HLS" : "Download")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glassEffect(
                            .regular.tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0)).interactive(),
                            in: .capsule
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        }
    }
}
