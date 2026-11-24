import SDMCore
import SwiftUI

public struct DownloadsTabView: View {
    @Bindable private var store: ParallelDownloadStore
    private let onPlayCompletedMedia: ((URL, String) -> Void)?

    @State private var showNewDownloadSheet = false
    @State private var filterSegment = 0
    @State private var errorAlertMessage: String?

    public init(
        store: ParallelDownloadStore,
        onPlayCompletedMedia: ((URL, String) -> Void)? = nil
    ) {
        self.store = store
        self.onPlayCompletedMedia = onPlayCompletedMedia
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
                    aggregateTelemetryBanner
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
                            downloadCardRow(item)
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
            }
            .navigationTitle("Downloads")
            .toolbar {
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
    }

    private var aggregateTelemetryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "bolt.horizontal.fill")
                .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
            Text("\(store.activeCount) Active Transfer\(store.activeCount == 1 ? "" : "s")")
                .font(.caption.weight(.semibold))
            Spacer()
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(store.aggregateBytesPerSecond), countStyle: .file))/s")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            ConcentricRectangle(corners: .concentric(minimum: 12), isUniform: true)
                .fill(Color.white.opacity(0.06))
        )
        .containerShape(.rect(cornerRadius: 16))
    }

    private func downloadCardRow(_ item: UnifiedDownloadItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.resolvedFilename)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Text(item.backend.displayTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(stateLabel(for: item.state))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 4)
                rowActionButtons(for: item)
            }

            // Per-segment Range visualization for multi-connection libcurl transfers
            if !item.segments.isEmpty {
                SegmentRangeBarView(segments: item.segments, totalBytes: item.totalBytes)
                    .frame(height: 8)
            } else if let fraction = item.progressFraction {
                ProgressView(value: fraction)
                    .tint(item.state == .completed ? .green : Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
            } else if item.isActive {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
            }

            HStack(spacing: 8) {
                let doneStr = ByteCountFormatter.string(fromByteCount: Int64(item.downloadedBytes), countStyle: .file)
                if let total = item.totalBytes, total > 0 {
                    let totalStr = ByteCountFormatter.string(fromByteCount: Int64(total), countStyle: .file)
                    Text("\(doneStr) / \(totalStr)")
                } else {
                    Text(doneStr)
                }

                if item.isActive && item.speedBytesPerSecond > 0 {
                    Text("•")
                    Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.speedBytesPerSecond), countStyle: .file))/s")
                        .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                }

                Spacer()

                if !item.segments.isEmpty && item.isActive {
                    Text("\(item.segments.count) segs")
                }

                if let eta = item.etaSeconds, eta > 0, eta.isFinite, item.isActive {
                    Text("ETA \(formatETA(eta))")
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)

            if let error = item.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
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
    private func rowActionButtons(for item: UnifiedDownloadItem) -> some View {
        HStack(spacing: 10) {
            switch item.state {
            case .downloading, .probing, .queued, .retrying:
                Button {
                    performAction { try await store.pause(item.id) }
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.borderless)

                Button {
                    performAction { try await store.cancel(item.id) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)

            case .paused:
                Button {
                    performAction { try await store.resume(item.id) }
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                }
                .buttonStyle(.borderless)

            case .failed, .cancelled:
                Button {
                    performAction { try await store.retry(item.id) }
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                }
                .buttonStyle(.borderless)

            case .completed:
                if let dst = item.destinationURL, isPlayableMedia(dst) {
                    Button {
                        onPlayCompletedMedia?(dst, item.resolvedFilename)
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
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
        case .finalizing: return "Finalizing"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private func formatETA(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s" }
        let m = total / 60
        let s = total % 60
        if m < 60 { return "\(m)m \(s)s" }
        return "\(m / 60)h \(m % 60)m"
    }
}

/// Visualizes per-range chunk progress for SDMCore multi-connection libcurl downloads.
private struct SegmentRangeBarView: View {
    let segments: [DownloadSegmentSnapshot]
    let totalBytes: UInt64?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))

                if let total = totalBytes, total > 0 {
                    ForEach(segments) { seg in
                        let startFrac = Double(seg.start) / Double(total)
                        let doneFrac = Double(seg.downloadedBytes) / Double(total)
                        let isComplete = seg.downloadedBytes >= seg.totalBytes
                        RoundedRectangle(cornerRadius: 3)
                            .fill(isComplete
                                ? Color.green
                                : Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
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
