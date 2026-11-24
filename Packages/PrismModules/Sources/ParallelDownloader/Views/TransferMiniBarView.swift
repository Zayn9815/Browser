import PrismCore
import SwiftUI
import VaultManager

/// Compact floating Liquid Glass bar displaying live download speed + ETA or Now Playing background audio.
/// Positioned neatly above the Omnibox (Bottom mode) or at the bottom safe area (Top mode).
public struct TransferMiniBarView: View {
    @Bindable private var downloadStore: ParallelDownloadStore
    @Bindable private var audioCenter: BackgroundAudioCenter
    @State private var themeEngine = PrismThemeEngine.shared
    private let onOpenDownloads: () -> Void

    public init(
        downloadStore: ParallelDownloadStore,
        audioCenter: BackgroundAudioCenter = .shared,
        onOpenDownloads: @escaping () -> Void
    ) {
        self.downloadStore = downloadStore
        self.audioCenter = audioCenter
        self.onOpenDownloads = onOpenDownloads
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        HStack(spacing: 10) {
            if downloadStore.activeCount > 0 {
                Button(action: onOpenDownloads) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(tokens.accent)

                        Text("\(downloadStore.activeCount)")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(tokens.primaryText)

                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(tokens.secondaryText)

                        Text("\(ByteCountFormatter.string(fromByteCount: Int64(downloadStore.aggregateBytesPerSecond), countStyle: .file))/s")
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(tokens.accent)

                        if !downloadStore.compactAggregateETA.isEmpty {
                            Text("•")
                                .font(.caption2)
                                .foregroundStyle(tokens.secondaryText)
                            Text(downloadStore.compactAggregateETA)
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .foregroundStyle(tokens.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Capsule())
                }
                .buttonStyle(.borderless)
                .glassEffect(.regular.interactive(), in: .capsule)
            } else if audioCenter.hasActiveTrack {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .foregroundStyle(tokens.accent)

                    Text(audioCenter.currentTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Button {
                        audioCenter.togglePlayPause()
                    } label: {
                        Image(systemName: audioCenter.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tokens.primaryText)
                            .frame(width: 28, height: 28)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)

                    Button {
                        audioCenter.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(tokens.secondaryText)
                            .frame(width: 26, height: 26)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
            }
        }
    }
}
