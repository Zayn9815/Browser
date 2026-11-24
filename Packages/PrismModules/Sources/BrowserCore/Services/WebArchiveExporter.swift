import Foundation
import VaultManager
import WebKit

public enum WebArchiveExportError: LocalizedError, Sendable {
    case noActiveWebView
    case archiveCreationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noActiveWebView:
            return "No active webpage is loaded to archive."
        case .archiveCreationFailed(let detail):
            return "Failed to save offline web archive: \(detail)"
        }
    }
}

@MainActor
public struct WebArchiveExporter {
    private let fileService: VaultFileService

    public init(fileService: VaultFileService = .shared) {
        self.fileService = fileService
    }

    public func exportCurrentPage(
        from webView: WKWebView,
        pageTitle: String,
        isPrivate: Bool
    ) async throws -> VaultItemRecordSnapshot {
        let archiveData: Data
        do {
            archiveData = try await withCheckedThrowingContinuation { continuation in
                webView.createWebArchiveData { result in
                    continuation.resume(with: result)
                }
            }
        } catch {
            throw WebArchiveExportError.archiveCreationFailed(error.localizedDescription)
        }

        let cleanTitle = pageTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty ? (webView.url?.host ?? "SavedPage") : pageTitle
        let filename = cleanTitle.lowercased().hasSuffix(".webarchive")
            ? cleanTitle
            : "\(cleanTitle).webarchive"

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("prism_\(UUID().uuidString).webarchive")
        try archiveData.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return try await fileService.registerCompletedFile(
            at: tempURL,
            preferredFilename: filename,
            mimeType: "application/x-webarchive",
            sourceURL: webView.url,
            isPrivate: isPrivate
        )
    }
}
