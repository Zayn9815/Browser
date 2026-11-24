import PrismCore
import SDMCore
import SwiftUI

public enum YTDLPPickerEngineChoice: String, CaseIterable, Identifiable, Sendable {
    case ytdlpParallel = "yt-dlp + Parallel"
    case ytdlpDirect = "yt-dlp Direct"
    case libcurlParallel = "libcurl Parallel"
    case urlSession = "URLSession"

    public var id: String { rawValue }
}

public struct YTDLPQualityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var downloadStore: ParallelDownloadStore
    @State private var themeEngine = PrismThemeEngine.shared

    private let sourceURL: URL
    private let sessionContext: BrowserSessionContext?
    private let onDownloadStarted: ((String) -> Void)?

    @State private var mediaInfo: YTDLPMediaInfo?
    @State private var selectedFormatID: String?
    @State private var engineChoice: YTDLPPickerEngineChoice = .ytdlpParallel
    @State private var saveToPrivateVault: Bool
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    public init(
        url: URL,
        sessionContext: BrowserSessionContext? = nil,
        downloadStore: ParallelDownloadStore,
        preloadedMediaInfo: YTDLPMediaInfo? = nil,
        onDownloadStarted: ((String) -> Void)? = nil
    ) {
        self.sourceURL = url
        self.sessionContext = sessionContext
        self.downloadStore = downloadStore
        self.onDownloadStarted = onDownloadStarted
        self._mediaInfo = State(initialValue: preloadedMediaInfo)
        self._selectedFormatID = State(initialValue: preloadedMediaInfo?.preferredFormat(for: downloadStore.defaultYTDLPQuality)?.id ?? preloadedMediaInfo?.formats.first?.id)
        self._isLoading = State(initialValue: preloadedMediaInfo == nil)
        self._saveToPrivateVault = State(initialValue: sessionContext?.isIncognito ?? false)
    }

    private var selectedFormat: YTDLPFormatOption? {
        mediaInfo?.formats.first(where: { $0.id == selectedFormatID }) ?? mediaInfo?.formats.first
    }

    public var body: some View {
        let tokens = themeEngine.tokens
        NavigationStack {
            List {
                // 1. Media Preview Card
                Section {
                    if isLoading {
                        HStack(spacing: 12) {
                            ProgressView()
                                .tint(tokens.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Extracting formats with yt-dlp…")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tokens.primaryText)
                                Text(sourceURL.host ?? sourceURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(tokens.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 6)
                    } else if let info = mediaInfo {
                        HStack(spacing: 12) {
                            if let thumb = info.thumbnailURL {
                                AsyncImage(url: thumb) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    default:
                                        tokens.cardSurface
                                            .overlay(
                                                Image(systemName: "film.fill")
                                                    .foregroundStyle(tokens.accent)
                                            )
                                    }
                                }
                                .frame(width: 84, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(info.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(tokens.primaryText)
                                    .lineLimit(2)

                                HStack(spacing: 6) {
                                    Text(info.extractorName)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(tokens.accentText)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(tokens.accent, in: Capsule())

                                    if let dur = info.formattedDuration {
                                        Text(dur)
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(tokens.secondaryText)
                                    }

                                    if !info.uploader.isEmpty {
                                        Text("• \(info.uploader)")
                                            .font(.caption2)
                                            .foregroundStyle(tokens.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    } else if let errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Extraction Failed", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(tokens.secondaryText)
                            Button("Retry Extraction") {
                                Task { await loadMediaInfo() }
                            }
                            .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 4)
                    }
                }
                .prismGlassListRow()

                // 2. Downloader Engine & Destination
                Section("Engine & Vault Destination") {
                    Picker("Downloader Engine", selection: $engineChoice) {
                        ForEach(YTDLPPickerEngineChoice.allCases) { choice in
                            Text(choice.rawValue).tag(choice)
                        }
                    }

                    Toggle(
                        "Save to Private Vault (Biometric Locked)",
                        isOn: $saveToPrivateVault
                    )
                }
                .prismGlassListRow()

                // 3. Quality / Format Picker (when yt-dlp formats loaded)
                if let info = mediaInfo, !info.formats.isEmpty,
                   (engineChoice == .ytdlpParallel || engineChoice == .ytdlpDirect) {
                    Section("Available Qualities (\(info.formats.count))") {
                        ForEach(info.formats) { format in
                            let isSelected = selectedFormat?.id == format.id
                            Button {
                                selectedFormatID = format.id
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: format.isAudioOnly ? "waveform" : "film")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(isSelected ? tokens.accent : tokens.secondaryText)
                                        .frame(width: 24)

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
                                        .font(.caption.weight(.semibold).monospacedDigit())
                                        .foregroundStyle(tokens.secondaryText)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(tokens.accent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .prismGlassListRow()
                }

                // 4. Primary Download Button
                Section {
                    Button {
                        Task { await startSelectedDownload() }
                    } label: {
                        Label(
                            isSubmitting
                                ? "Starting…"
                                : (selectedFormat.map { "Download \($0.label)" } ?? "Download Now"),
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .foregroundStyle(tokens.accentText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(isSubmitting || (isLoading && (engineChoice == .ytdlpParallel || engineChoice == .ytdlpDirect)))
                    .buttonStyle(.glassProminent)
                    .tint(tokens.accent)
                }
                .listRowBackground(Color.clear)
            }
            .listStyle(.insetGrouped)
            .prismThemedScrollChrome()
            .navigationTitle("yt-dlp Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if mediaInfo == nil {
                    await loadMediaInfo()
                }
            }
        }
        .prismThemedSheetChrome()
        .presentationDetents([.large, .medium])
    }

    private func loadMediaInfo() async {
        isLoading = true
        errorMessage = nil
        do {
            let info = try await YTDLPExtractorService.shared.extractMediaInfo(
                url: sourceURL,
                sessionContext: sessionContext
            )
            mediaInfo = info
            selectedFormatID = info.preferredFormat(for: downloadStore.defaultYTDLPQuality)?.id ?? info.formats.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func startSelectedDownload() async {
        isSubmitting = true
        defer { isSubmitting = false }

        let effectiveContext = BrowserSessionContext(
            userAgent: sessionContext?.userAgent,
            cookieHeader: sessionContext?.cookieHeader,
            pageReferer: sessionContext?.pageReferer ?? sourceURL.absoluteString,
            origin: sessionContext?.origin,
            suggestedFilename: sessionContext?.suggestedFilename,
            isIncognito: saveToPrivateVault
        )

        do {
            switch engineChoice {
            case .ytdlpParallel, .ytdlpDirect:
                guard let info = mediaInfo, let format = selectedFormat else { return }
                _ = try await downloadStore.enqueueYTDLPDownload(
                    mediaInfo: info,
                    format: format,
                    preferDirectYTDLP: engineChoice == .ytdlpDirect,
                    isPrivateVault: saveToPrivateVault,
                    sessionContext: effectiveContext
                )
                onDownloadStarted?("Downloading \(info.title) (\(format.label))…")
            case .libcurlParallel:
                let targetURL = selectedFormat?.videoURL ?? selectedFormat?.audioURL ?? sourceURL
                _ = try await downloadStore.enqueueHTTPDownload(
                    url: targetURL,
                    sessionContext: effectiveContext,
                    preferredEngine: .libcurl,
                    connectionLimit: downloadStore.defaultConnectionsPerDownload,
                    bandwidthLimitBytesPerSec: nil
                )
                onDownloadStarted?("Downloading via libcurl Parallel…")
            case .urlSession:
                let targetURL = selectedFormat?.videoURL ?? selectedFormat?.audioURL ?? sourceURL
                _ = try await downloadStore.enqueueHTTPDownload(
                    url: targetURL,
                    sessionContext: effectiveContext,
                    preferredEngine: .urlSession,
                    connectionLimit: 1,
                    bandwidthLimitBytesPerSec: nil
                )
                onDownloadStarted?("Downloading via iOS URLSession…")
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
