import PrismCore
import SDMCore
import SwiftUI
import UIKit

public enum NewDownloadEngineChoice: String, CaseIterable, Identifiable, Sendable {
    case autoSmart = "Auto / Smart Hybrid"
    case ytdlp = "yt-dlp (Universal)"
    case libcurlParallel = "libcurl Parallel"
    case urlSession = "iOS URLSession"
    case ffmpegHLS = "FFmpeg HLS Parallel"

    public var id: String { rawValue }
}

public struct NewDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: ParallelDownloadStore
    @State private var themeEngine = PrismThemeEngine.shared

    @State private var urlInput = ""
    @State private var customFilename = ""
    @State private var engineChoice: NewDownloadEngineChoice
    @State private var connectionCount: Int
    @State private var bandwidthLimitMBps: Double = 0
    @State private var saveToPrivateVault = false

    // yt-dlp inline quality extraction state
    @State private var extractedInfo: YTDLPMediaInfo?
    @State private var selectedFormatID: String?
    @State private var isExtractingQualities = false
    @State private var preferDirectYTDLP = false

    @State private var errorMessage: String?
    @State private var isSubmitting = false

    public init(store: ParallelDownloadStore) {
        self.store = store
        let initialEngine: NewDownloadEngineChoice = {
            switch store.defaultDownloaderMode {
            case .smartHybrid: return .autoSmart
            case .ytdlpUniversal: return .ytdlp
            case .libcurlParallel: return .libcurlParallel
            case .urlSessionBackground: return .urlSession
            }
        }()
        self._engineChoice = State(initialValue: initialEngine)
        self._connectionCount = State(initialValue: store.defaultConnectionsPerDownload)
    }

    private var parsedURL: URL? {
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }
        return url
    }

    private var shouldShowYTDLPControls: Bool {
        if engineChoice == .ytdlp { return true }
        if engineChoice == .autoSmart, let url = parsedURL {
            return YTDLPURLMatcher.shouldPreferYTDLP(for: url)
        }
        return false
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            Form {
                Section("Download URL") {
                    TextField("https://youtube.com/watch?v=... or file URL", text: $urlInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: urlInput) { _, newValue in
                            extractedInfo = nil
                            selectedFormatID = nil
                            let lower = newValue.lowercased()
                            if lower.contains(".m3u8") || lower.contains(".mpd") {
                                engineChoice = .ffmpegHLS
                            }
                        }

                    if let pasted = UIPasteboard.general.string,
                       pasted.lowercased().hasPrefix("http") {
                        Button {
                            urlInput = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
                        } label: {
                            Label("Paste from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    }

                    TextField("Optional Filename", text: $customFilename)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .prismGlassListRow()

                Section("Downloader Engine") {
                    Picker("Engine", selection: $engineChoice) {
                        ForEach(NewDownloadEngineChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }

                    Toggle("Save to Private Vault", isOn: $saveToPrivateVault)

                    if shouldShowYTDLPControls {
                        Button {
                            Task { await loadYTDLPQualities() }
                        } label: {
                            HStack {
                                if isExtractingQualities {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(tokens.accent)
                                    Text("Extracting formats with yt-dlp…")
                                } else {
                                    Label(
                                        extractedInfo == nil ? "Load Qualities (yt-dlp)" : "Reload Qualities",
                                        systemImage: "sparkles.tv.fill"
                                    )
                                }
                            }
                        }
                        .disabled(parsedURL == nil || isExtractingQualities)

                        Toggle("Use Direct yt-dlp Mode (Skip Parallel Mux)", isOn: $preferDirectYTDLP)
                    } else if engineChoice == .libcurlParallel || engineChoice == .autoSmart {
                        Stepper("Parallel Connections: \(connectionCount)", value: $connectionCount, in: 1...16)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Bandwidth Cap")
                                Spacer()
                                Text(bandwidthLimitMBps <= 0 ? "Unlimited" : String(format: "%.1f MB/s", bandwidthLimitMBps))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $bandwidthLimitMBps, in: 0...50, step: 0.5)
                                .tint(tokens.accent)
                        }
                    } else if engineChoice == .urlSession {
                        Text("Uses iOS native background URLSession transfer daemon (single connection, continues in background).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if engineChoice == .ffmpegHLS {
                        Text("Two-Stage Parallel Chunked HLS Downloader + local FFmpeg Libavformat (-c copy, +faststart) into .mp4.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .prismGlassListRow()

                if let info = extractedInfo, !info.formats.isEmpty, shouldShowYTDLPControls {
                    Section("Extracted Qualities — \(info.title)") {
                        ForEach(info.formats) { format in
                            let isSelected = (selectedFormatID ?? info.formats.first?.id) == format.id
                            Button {
                                selectedFormatID = format.id
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(format.label)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(tokens.primaryText)
                                        Text(format.detail)
                                            .font(.caption2)
                                            .foregroundStyle(tokens.secondaryText)
                                    }
                                    Spacer()
                                    Text(format.formattedSizeLabel)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(tokens.secondaryText)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(tokens.accent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .prismGlassListRow()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .prismGlassListRow()
                }

                Section {
                    Button {
                        Task { await submitDownload() }
                    } label: {
                        Label(
                            isSubmitting ? "Starting…" : "Start Download",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(tokens.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(isSubmitting || parsedURL == nil)
                    .buttonStyle(.glassProminent)
                    .tint(tokens.accent)
                }
                .listRowBackground(Color.clear)
            }
            .prismThemedScrollChrome()
            .navigationTitle("New Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .prismThemedSheetChrome()
        .presentationDetents([.large, .medium])
    }

    private func loadYTDLPQualities() async {
        guard let url = parsedURL else { return }
        errorMessage = nil
        isExtractingQualities = true
        defer { isExtractingQualities = false }
        do {
            let info = try await YTDLPExtractorService.shared.extractMediaInfo(
                url: url,
                sessionContext: BrowserSessionContext(isIncognito: saveToPrivateVault)
            )
            extractedInfo = info
            selectedFormatID = info.preferredFormat(for: store.defaultYTDLPQuality)?.id ?? info.formats.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submitDownload() async {
        errorMessage = nil
        guard let url = parsedURL else {
            errorMessage = "Enter a valid http:// or https:// URL."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let filename = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let session = BrowserSessionContext(
            suggestedFilename: filename.isEmpty ? nil : filename,
            isIncognito: saveToPrivateVault
        )

        do {
            if shouldShowYTDLPControls {
                let info: YTDLPMediaInfo
                if let existing = extractedInfo {
                    info = existing
                } else {
                    info = try await YTDLPExtractorService.shared.extractMediaInfo(url: url, sessionContext: session)
                    extractedInfo = info
                }
                guard let chosenFormat = info.formats.first(where: { $0.id == selectedFormatID })
                    ?? info.preferredFormat(for: store.defaultYTDLPQuality)
                    ?? info.formats.first else {
                    throw YTDLPExtractorError.noPlayableFormats
                }
                _ = try await store.enqueueYTDLPDownload(
                    mediaInfo: info,
                    format: chosenFormat,
                    preferDirectYTDLP: preferDirectYTDLP,
                    isPrivateVault: saveToPrivateVault,
                    sessionContext: session
                )
            } else {
                switch engineChoice {
                case .autoSmart, .libcurlParallel:
                    let capBytes: UInt64? = bandwidthLimitMBps > 0 ? UInt64(bandwidthLimitMBps * 1_000_000) : nil
                    _ = try await store.enqueueHTTPDownload(
                        url: url,
                        sessionContext: session,
                        preferredEngine: .libcurl,
                        connectionLimit: connectionCount,
                        bandwidthLimitBytesPerSec: capBytes
                    )
                case .urlSession:
                    _ = try await store.enqueueHTTPDownload(
                        url: url,
                        sessionContext: session,
                        preferredEngine: .urlSession,
                        connectionLimit: 1,
                        bandwidthLimitBytesPerSec: nil
                    )
                case .ffmpegHLS:
                    _ = try await store.enqueueHLSStreamMux(
                        manifestURL: url,
                        variantTitle: filename.isEmpty ? nil : filename,
                        sessionContext: session
                    )
                case .ytdlp:
                    break
                }
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
