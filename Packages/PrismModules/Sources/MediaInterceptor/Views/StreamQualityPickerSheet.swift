import PrismPlayer
import SwiftUI

public struct StreamQualityPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let item: InterceptedMediaItem
    private let onSelectDownload: (InterceptedMediaItem, HLSStreamVariant?) -> Void
    private let onSelectPlay: (InterceptedMediaItem, HLSStreamVariant?) -> Void

    @State private var variants: [HLSStreamVariant] = []
    @State private var selectedVariantID: String?
    @State private var isLoadingVariants = false
    @State private var loadError: String?

    private let inspector = HLSManifestInspector()

    public init(
        item: InterceptedMediaItem,
        onSelectDownload: @escaping (InterceptedMediaItem, HLSStreamVariant?) -> Void,
        onSelectPlay: @escaping (InterceptedMediaItem, HLSStreamVariant?) -> Void
    ) {
        self.item = item
        self.onSelectDownload = onSelectDownload
        self.onSelectPlay = onSelectPlay
        self._variants = State(initialValue: item.variants)
        self._selectedVariantID = State(initialValue: item.variants.first?.id)
    }

    private var selectedVariant: HLSStreamVariant? {
        variants.first(where: { $0.id == selectedVariantID })
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("Detected Stream") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(2)
                        Text(item.streamURL.host ?? item.streamURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Format: \(item.containerHint.rawValue.uppercased())")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                    }
                }

                if item.containerHint == .m3u8 {
                    Section("Available Quality Variants") {
                        if isLoadingVariants {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Inspecting #EXT-X-STREAM-INF playlist…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if variants.isEmpty {
                            Text(loadError ?? "Single media playlist detected (best available stream will be downloaded).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(variants) { variant in
                                Button {
                                    selectedVariantID = variant.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(variant.displayLabel)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(.primary)
                                            if let res = variant.resolution {
                                                Text("\(Int(res.width)) × \(Int(res.height))")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if selectedVariantID == variant.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        onSelectDownload(item, selectedVariant)
                        dismiss()
                    } label: {
                        Label(
                            selectedVariant.map { "Download \($0.displayLabel)" } ?? "Download Stream",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color(red: 220.0 / 255.0, green: 20.0 / 255.0, blue: 60.0 / 255.0))

                    Button {
                        onSelectPlay(item, selectedVariant)
                        dismiss()
                    } label: {
                        Label("Play in PrismPlayer", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                }
            }
            .navigationTitle("Stream Quality")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                guard item.containerHint == .m3u8, variants.isEmpty else { return }
                isLoadingVariants = true
                defer { isLoadingVariants = false }
                do {
                    let parsed = try await inspector.fetchVariants(
                        from: item.streamURL,
                        sessionContext: item.sessionContext
                    )
                    variants = parsed
                    selectedVariantID = parsed.first?.id
                } catch {
                    loadError = error.localizedDescription
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
