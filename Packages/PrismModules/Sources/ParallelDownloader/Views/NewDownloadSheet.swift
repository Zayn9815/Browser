import SDMCore
import SwiftUI
import UIKit

public struct NewDownloadSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var store: ParallelDownloadStore

    @State private var urlInput = ""
    @State private var customFilename = ""
    @State private var selectedBackend: PrismTransferBackendKind = .sdmLibcurlRange
    @State private var connectionCount: Int = 8
    @State private var bandwidthLimitMBps: Double = 0
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    public init(store: ParallelDownloadStore) {
        self.store = store
        self._selectedBackend = State(initialValue: store.preferredHTTPBackend == .libcurl ? .sdmLibcurlRange : .sdmBackgroundSession)
        self._connectionCount = State(initialValue: store.defaultConnectionsPerDownload)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Download URL") {
                    TextField("https://example.com/file.mp4 or .m3u8", text: $urlInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: urlInput) { _, newValue in
                            let lower = newValue.lowercased()
                            if lower.contains(".m3u8") || lower.contains(".mpd") {
                                selectedBackend = .ffmpegHLSMuxer
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

                Section("Transfer Engine") {
                    Picker("Engine", selection: $selectedBackend) {
                        ForEach(PrismTransferBackendKind.allCases, id: \.self) { backend in
                            Text(backend.displayTitle).tag(backend)
                        }
                    }

                    if selectedBackend == .sdmLibcurlRange {
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
                                .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                        }
                    } else if selectedBackend == .sdmBackgroundSession {
                        Text("Uses iOS native background URLSession transfer daemon (single connection, continues in background).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Streams HLS/DASH manifests via FFmpeg Libavformat (-c copy, aac_adtstoasc) into a faststart .mp4 file.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .disabled(isSubmitting || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.glassProminent)
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                }
            }
            .navigationTitle("New Download")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func submitDownload() async {
        errorMessage = nil
        let trimmed = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            errorMessage = "Enter a valid http:// or https:// URL."
            return
        }

        isSubmitting = true
        defer { isSubmitting = false }

        let filename = customFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let session: BrowserSessionContext? = filename.isEmpty
            ? nil
            : BrowserSessionContext(suggestedFilename: filename)

        do {
            switch selectedBackend {
            case .sdmLibcurlRange:
                let capBytes: UInt64? = bandwidthLimitMBps > 0 ? UInt64(bandwidthLimitMBps * 1_000_000) : nil
                _ = try await store.enqueueHTTPDownload(
                    url: url,
                    sessionContext: session,
                    preferredEngine: .libcurl,
                    connectionLimit: connectionCount,
                    bandwidthLimitBytesPerSec: capBytes
                )
            case .sdmBackgroundSession:
                _ = try await store.enqueueHTTPDownload(
                    url: url,
                    sessionContext: session,
                    preferredEngine: .urlSession,
                    connectionLimit: 1,
                    bandwidthLimitBytesPerSec: nil
                )
            case .ffmpegHLSMuxer:
                _ = try await store.enqueueHLSStreamMux(
                    manifestURL: url,
                    variantTitle: filename.isEmpty ? nil : filename,
                    sessionContext: session
                )
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
