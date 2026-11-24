import SwiftUI
import VaultManager

/// Compact iOS 26 `tabViewBottomAccessory` bar displaying live download throughput or Now Playing audio.
/// Strictly avoids nesting SwiftUI `Menu` inside the accessory to prevent iOS 26 AttributeGraph cycles.
public struct TransferMiniBarView: View {
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    @Bindable private var downloadStore: ParallelDownloadStore
    @Bindable private var audioCenter: BackgroundAudioCenter
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
        HStack(spacing: 10) {
            if downloadStore.activeCount > 0 {
                Button(action: onOpenDownloads) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))

                        if placement == .inline {
                            Text("\(downloadStore.activeCount) • \(ByteCountFormatter.string(fromByteCount: Int64(downloadStore.aggregateBytesPerSecond), countStyle: .file))/s")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                        } else {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(downloadStore.activeCount) active download\(downloadStore.activeCount == 1 ? "" : "s")")
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text("\(ByteCountFormatter.string(fromByteCount: Int64(downloadStore.aggregateBytesPerSecond), countStyle: .file))/s")
                                    .font(.caption2.weight(.bold).monospacedDigit())
                                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            } else if audioCenter.hasActiveTrack {
                Image(systemName: "waveform")
                    .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))

                Text(audioCenter.currentTitle)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button {
                    audioCenter.togglePlayPause()
                } label: {
                    Image(systemName: audioCenter.isPlaying ? "pause.fill" : "play.fill")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)

                if placement != .inline {
                    Button {
                        audioCenter.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}
