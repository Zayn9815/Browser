import PrismCore
import SDMCore
import SwiftUI

public struct DownloadsTabView: View {
    @Bindable private var store: ParallelDownloadStore
    @State private var themeEngine = PrismThemeEngine.shared
    private let onPlayCompletedMedia: ((URL, String) -> Void)?
    private let onDismiss: (() -> Void)?

    @State private var showNewDownloadSheet = false
    @State private var filterSegment = 0
    @State private var errorAlertMessage: String?

    public init(
        store: ParallelDownloadStore,
        onPlayCompletedMedia: ((URL, String) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.store = store
        self.onPlayCompletedMedia = onPlayCompletedMedia
        self.onDismiss = onDismiss
    }

    private var displayedItems: [UnifiedDownloadItem] {
        switch filterSegment {
        case 1:
            return store.items.filter(\.isActive)
        case 2:
            return store.items.filter { $0.state == .completed }
        default:
            return store.items
        }
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filter", selection: $filterSegment) {
                    Text("All (\(store.items.count))").tag(0)
                    Text("Active (\(store.activeCount))").tag(1)
                    Text("Done").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                if store.activeCount > 0 {
                    aggregateTelemetryBanner(tokens: tokens)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }

                List {
                    if let startupErr = store.engineStartupError {
                        Section {
                            Label(startupErr, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }

                    if displayedItems.isEmpty {
                        ContentUnavailableView(
                            filterSegment == 1 ? "No Active Transfers" : "No Downloads Yet",
                            systemImage: "arrow.down.circle",
                            description: Text("Tap + to add a URL, or download any file or video stream directly from the browser or PrismPlayer.")
                        )
                    } else {
                        ForEach(displayedItems) { item in
                            downloadCardRow(item, tokens: tokens)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if item.state == .completed {
                                        Button(role: .destructive) {
                                            performAction { try await store.deleteWithFinalizedFile(item.id) }
                                        } label: {
                                            Label("Delete File", systemImage: "trash.fill")
                                        }
                                    }
                                    Button {
                                        performAction { try await store.removeFromHistory(item.id) }
                                    } label: {
                                        Label("Remove", systemImage: "xmark.circle")
                                    }
                                    .tint(.orange)
                                }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(tokens.canvasBackground)
            }
            .background(tokens.canvasBackground.ignoresSafeArea())
            .navigationTitle("Downloads")
            .toolbar {
                if let onDismiss {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Done", action: onDismiss)
                            .fontWeight(.semibold)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewDownloadSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add Download")
                }
            }
            .sheet(isPresented: $showNewDownloadSheet) {
                NewDownloadSheet(store: store)
            }
            .alert("Transfer Action Failed", isPresented: Binding(
                get: { errorAlertMessage != nil },
                set: { if !$0 { errorAlertMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorAlertMessage = nil }
            } message: {
                Text(errorAlertMessage ?? "")
            }
        }
        .tint(tokens.accent)
    }

    private func aggregateTelemetryBanner(tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.fill")
                .foregroundStyle(tokens.accent)
            Text("\(store.activeCount) Active Transfer\(store.activeCount == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
                .foregroundStyle(tokens.primaryText)
            Spacer()
            HStack(spacing: 6) {
                Text("\(ByteCountFormatter.string(fromByteCount: Int64(store.aggregateBytesPerSecond), countStyle: .file))/s")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(tokens.accent)
                if !store.compactAggregateETA.isEmpty {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(tokens.secondaryText)
                    Text(store.compactAggregateETA)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(tokens.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
                .fill(tokens.cardSurface)
        )
        .containerShape(.rect(cornerRadius: 16))
    }

    private func downloadCardRow(_ item: UnifiedDownloadItem, tokens: PrismThemeTokens) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.resolvedFilename)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tokens.primaryText)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.backend.displayTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tokens.accent)
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(tokens.secondaryText)
                        Text(stateLabel(for: item.state))
                            .font(.caption2)
                            .foregroundStyle(tokens.secondaryText)
                    }
                }
                Spacer(minLength: 4)
                rowActionButtons(for: item, tokens: tokens)
            }

            // Segmented chunk visualization for BOTH multi-range HTTP and parallel chunked HLS
            if !item.segments.isEmpty {
                SegmentRangeBarView(
                    segments: item.segments,
                    totalBytes: item.totalBytes,
                    accentColor: tokens.accent,
                    trackColor: tokens.hairline
                )
                .frame(height: 8)
            } else if let fraction = item.progressFraction {
                ProgressView(value: fraction)
                    .tint(item.state == .completed ? .green : tokens.accent)
            } else if item.isActive {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(tokens.accent)
            }

            HStack(spacing: 6) {
                Text(item.formattedSizeRatio)
                    .foregroundStyle(tokens.secondaryText)

                if item.isActive && item.speedBytesPerSecond > 0 {
                    Text("•")
                        .foregroundStyle(tokens.secondaryText)
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.speedBytesPerSecond), countStyle: .file))/s")
                        .foregroundStyle(tokens.accent)
                        .fontWeight(.semibold)
                }

                Spacer(minLength: 4)

                if !item.segments.isEmpty && item.isActive {
                    Text("\(item.segments.count) ch")
                        .foregroundStyle(tokens.tertiaryText)
                }

                if item.isActive && !item.formattedETALabel.isEmpty {
                    Text(item.formattedETALabel)
                        .foregroundStyle(tokens.primaryText.opacity(0.86))
                        .fontWeight(.medium)
                }
            }
            .font(.caption2.monospacedDigit())

            if let error = item.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(tokens.destructive)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if item.state == .completed, let dst = item.destinationURL {
                Button {
                    onPlayCompletedMedia?(dst, item.resolvedFilename)
                } label: {
                    Label("Play in PrismPlayer", systemImage: "play.fill")
                }

                ShareLink(item: dst) {
                    Label("Share File", systemImage: "square.and.arrow.up")
                }
            }

            Button {
                performAction { try await store.removeFromHistory(item.id) }
            } label: {
                Label("Remove from History (Keep File)", systemImage: "clock.arrow.circlepath")
            }

            if item.state == .completed {
                Button(role: .destructive) {
                    performAction { try await store.deleteWithFinalizedFile(item.id) }
                } label: {
                    Label("Delete File & History", systemImage: "trash.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func rowActionButtons(for item: UnifiedDownloadItem, tokens: PrismThemeTokens) -> some View {
        HStack(spacing: 10) {
            switch item.state {
            case .downloading, .probing, .queued, .retrying:
                Button {
                    performAction { try await store.pause(item.id) }
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tokens.primaryText)
                }
                .buttonStyle(.borderless)

                Button {
                    performAction { try await store.cancel(item.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tokens.secondaryText)
                }
                .buttonStyle(.borderless)

            case .paused:
                Button {
                    performAction { try await store.resume(item.id) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tokens.accent)
                }
                .buttonStyle(.borderless)

            case .failed, .cancelled:
                Button {
                    performAction { try await store.retry(item.id) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(tokens.accent)
                }
                .buttonStyle(.borderless)

            case .completed:
                if let dst = item.destinationURL, isPlayableMedia(dst) {
                    Button {
                        onPlayCompletedMedia?(dst, item.resolvedFilename)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(tokens.accent)
                    }
                    .buttonStyle(.borderless)
                }

            default:
                EmptyView()
            }
        }
    }

    private func performAction(_ work: @escaping () async throws -> Void) {
        Task { @MainActor in
            do {
                try await work()
            } catch {
                errorAlertMessage = error.localizedDescription
            }
        }
    }

    private func isPlayableMedia(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "ts", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"].contains(ext)
    }

    private func stateLabel(for state: DownloadState) -> String {
        switch state {
        case .created: return "Created"
        case .probing: return "Probing"
        case .queued: return "Queued"
        case .downloading: return "Downloading"
        case .pausing: return "Pausing"
        case .paused: return "Paused"
        case .retrying: return "Retrying"
        case .finalizing: return "Remuxing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
}

/// Visualizes per-range chunk progress for both SDMCore multi-connection libcurl and Parallel HLS downloads.
private struct SegmentRangeBarView: View {
    let segments: [DownloadSegmentSnapshot]
    let totalBytes: UInt64?
    let accentColor: Color
    let trackColor: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(trackColor)

                if let total = totalBytes, total > 0 {
                    ForEach(segments) { seg in
                        let startFrac = Double(seg.start) / Double(total)
                        let doneFrac = Double(seg.downloadedBytes) / Double(total)
                        let isComplete = seg.downloadedBytes >= seg.totalBytes
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isComplete ? Color.green : accentColor)
                            .frame(
                                width: max(2, geo.size.width * CGFloat(doneFrac)),
                                height: geo.size.height
                            )
                            .offset(x: geo.size.width * CGFloat(startFrac))
                    }
                }
            }
            .clipShape(Capsule())
        }
    }
}
