import Foundation
import Libavcodec
import Libavformat
import SDMCore

@MainActor
public protocol ParallelDownloadCoordinating: AnyObject {
    var items: [UnifiedDownloadItem] { get }
    var activeCount: Int { get }
    var aggregateBytesPerSecond: UInt64 { get }
    var preferredHTTPBackend: DownloadEngineKind { get set }
    var defaultConnectionsPerDownload: Int { get set }

    @discardableResult
    func enqueueHTTPDownload(
        url: URL,
        sessionContext: BrowserSessionContext?,
        preferredEngine: DownloadEngineKind?,
        connectionLimit: Int?,
        bandwidthLimitBytesPerSec: UInt64?
    ) async throws -> UUID

    @discardableResult
    func enqueueHLSStreamMux(
        manifestURL: URL,
        variantTitle: String?,
        sessionContext: BrowserSessionContext?
    ) async throws -> UUID

    func pause(_ id: UUID) async throws
    func resume(_ id: UUID) async throws
    func cancel(_ id: UUID) async throws
    func retry(_ id: UUID) async throws
    func removeFromHistory(_ id: UUID) async throws
    func deleteWithFinalizedFile(_ id: UUID) async throws
}

public enum ParallelDownloadBackgroundRelay: Sendable {
    public static func handleEvents(
        identifier: String,
        completionHandler: @escaping @Sendable () -> Void
    ) {
        SDMCoreBackgroundSessionEvents.handle(
            identifier: identifier,
            completionHandler: completionHandler
        )
    }
}

public enum ParallelDownloaderEngineDiagnostics: Sendable {
    public static var sdmCoreVersionSummary: String {
        "SDMCore v\(SDMCoreInfo.engineVersion) (ABI v\(SDMCoreInfo.engineABIVersion)) • \(SDMCoreInfo.libcurlVersion)"
    }

    public static var ffmpegVersionSummary: String {
        let avf = avformat_version()
        let avc = avcodec_version()
        let avfMajor = (avf >> 16) & 0xFF
        let avfMinor = (avf >> 8) & 0xFF
        let avcMajor = (avc >> 16) & 0xFF
        let avcMinor = (avc >> 8) & 0xFF
        return "Libavformat \(avfMajor).\(avfMinor) • Libavcodec \(avcMajor).\(avcMinor)"
    }
}
