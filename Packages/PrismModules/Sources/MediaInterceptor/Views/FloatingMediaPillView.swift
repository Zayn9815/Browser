import PrismCore
import SwiftUI

public struct FloatingMediaPillView: View {
    @State private var themeEngine = PrismThemeEngine.shared
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
        let tokens = themeEngine.tokens
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
                                .foregroundStyle(tokens.accent)
                            Text("Play")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(tokens.primaryText)
                            if let height = item.videoHeight, height > 0 {
                                Text("\(height)p")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(tokens.secondaryText)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .prismGlassPill(interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)

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
                        .foregroundStyle(tokens.accentText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .prismGlassPill(prominent: true, interactive: true)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
            .sensoryFeedback(.impact(flexibility: .solid, intensity: 0.7), trigger: hapticCounter)
        }
    }
}
