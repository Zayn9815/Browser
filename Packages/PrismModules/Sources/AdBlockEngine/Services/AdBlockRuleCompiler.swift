import CryptoKit
import Foundation
import Observation
import WebKit

public enum AdBlockCompilerError: LocalizedError, Sendable {
    case manifestMissing
    case shardMissing(String)
    case shardRuleCeilingExceeded(identifier: String, count: Int)
    case invalidAllowlistJSON

    public var errorDescription: String? {
        switch self {
        case .manifestMissing:
            return "Offline AdBlockShards/manifest.json was not found in the app bundle."
        case .shardMissing(let filename):
            return "AdBlock shard file is missing: \(filename)"
        case .shardRuleCeilingExceeded(let identifier, let count):
            return "AdBlock shard \(identifier) has \(count) rules, exceeding WebKit's 150,000 rule ceiling."
        case .invalidAllowlistJSON:
            return "Unable to encode per-site allowlist JSON."
        }
    }
}

@Observable
@MainActor
public final class AdBlockRuleCompiler: AdBlockRuleProviding {
    public static let shared = AdBlockRuleCompiler()
    public static let webKitRuleLimit = 150_000
    public static let recommendedShardCeiling = 125_000

    public private(set) var isReady = false
    public private(set) var compiledRuleLists: [WKContentRuleList] = []
    public private(set) var loadedManifest: AdBlockManifest?
    public private(set) var totalActiveRules: Int = 0
    public private(set) var lastErrorMessage: String?

    private let bundle: Bundle
    private var compiledBaseShards: [WKContentRuleList] = []
    private var cachedAllowlistKey: String?
    private var cachedAllowlistRuleList: WKContentRuleList?
    private var preparationTask: Task<[WKContentRuleList], Error>?

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    public func prepareRuleLists(allowlistedHosts: Set<String> = []) async throws -> [WKContentRuleList] {
        let baseLists: [WKContentRuleList]
        if !compiledBaseShards.isEmpty {
            baseLists = compiledBaseShards
        } else if let inFlight = preparationTask {
            baseLists = try await inFlight.value
        } else {
            let task = Task { @MainActor [weak self] () throws -> [WKContentRuleList] in
                guard let self else { return [] }
                return try await self.compileOrLookupBaseShards()
            }
            preparationTask = task
            do {
                baseLists = try await task.value
                compiledBaseShards = baseLists
                preparationTask = nil
            } catch {
                preparationTask = nil
                lastErrorMessage = error.localizedDescription
                throw error
            }
        }

        var combined = baseLists
        if let allowlist = try await compileAllowlistIfNeeded(hosts: allowlistedHosts) {
            combined.append(allowlist)
        }
        compiledRuleLists = combined
        isReady = true
        return combined
    }

    public func apply(
        to userContentController: WKUserContentController,
        siteHost: String?,
        allowlistedHosts: Set<String>
    ) async {
        userContentController.removeAllContentRuleLists()

        if allowlistedHosts.contains("*") {
            return
        }

        if let host = siteHost?.lowercased(), allowlistedHosts.contains(host) {
            return
        }

        do {
            let lists = try await prepareRuleLists(allowlistedHosts: allowlistedHosts)
            for list in lists {
                userContentController.add(list)
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Generates valid WebKit `ignore-previous-rules` JSON for allowlisted hosts.
    public static func makeAllowlistJSON(for hosts: Set<String>) throws -> String {
        let normalized = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E } }
            .sorted()

        guard !normalized.isEmpty else {
            return "[]"
        }

        let rules: [[String: Any]] = [[
            "trigger": [
                "url-filter": ".*",
                "if-domain": normalized.map { "*\($0)" },
            ],
            "action": [
                "type": "ignore-previous-rules",
            ],
        ]]

        let data = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            throw AdBlockCompilerError.invalidAllowlistJSON
        }
        return string
    }

    public static func validateManifest(_ manifest: AdBlockManifest) throws {
        for shard in manifest.shards {
            if shard.ruleCount > webKitRuleLimit {
                throw AdBlockCompilerError.shardRuleCeilingExceeded(identifier: shard.identifier, count: shard.ruleCount)
            }
        }
    }

    // MARK: - Private Compilation & Disk Caching

    private func compileOrLookupBaseShards() async throws -> [WKContentRuleList] {
        guard let manifest = AdBlockManifestLoader.loadBundledManifest(in: bundle) else {
            throw AdBlockCompilerError.manifestMissing
        }
        try Self.validateManifest(manifest)
        loadedManifest = manifest

        let store = WKContentRuleListStore.default()!
        var results: [WKContentRuleList] = []
        var activeRuleCount = 0

        for shard in manifest.shards {
            if let cached = await lookupRuleList(identifier: shard.identifier, in: store) {
                results.append(cached)
                activeRuleCount += shard.ruleCount
                continue
            }

            let stem = (shard.filename as NSString).deletingPathExtension
            let ext = (shard.filename as NSString).pathExtension
            guard let fileURL = bundle.url(
                forResource: stem,
                withExtension: ext.isEmpty ? "json" : ext,
                subdirectory: "AdBlockShards"
            ) else {
                throw AdBlockCompilerError.shardMissing(shard.filename)
            }

            let jsonString = try String(contentsOf: fileURL, encoding: .utf8)
            let compiled = try await compileRuleList(identifier: shard.identifier, json: jsonString, in: store)
            results.append(compiled)
            activeRuleCount += shard.ruleCount
        }

        totalActiveRules = activeRuleCount
        return results
    }

    private func compileAllowlistIfNeeded(hosts: Set<String>) async throws -> WKContentRuleList? {
        let sorted = hosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
            .sorted()

        guard !sorted.isEmpty else {
            cachedAllowlistKey = nil
            cachedAllowlistRuleList = nil
            return nil
        }

        let joined = sorted.joined(separator: ",")
        let digest = SHA256.hash(data: Data(joined.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        let identifier = "prism_allowlist_\(digest)"

        if cachedAllowlistKey == identifier, let cachedAllowlistRuleList {
            return cachedAllowlistRuleList
        }

        let store = WKContentRuleListStore.default()!
        if let existing = await lookupRuleList(identifier: identifier, in: store) {
            cachedAllowlistKey = identifier
            cachedAllowlistRuleList = existing
            return existing
        }

        let json = try Self.makeAllowlistJSON(for: Set(sorted))
        let compiled = try await compileRuleList(identifier: identifier, json: json, in: store)
        cachedAllowlistKey = identifier
        cachedAllowlistRuleList = compiled
        return compiled
    }

    private func lookupRuleList(identifier: String, in store: WKContentRuleListStore) async -> WKContentRuleList? {
        await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, _ in
                continuation.resume(returning: list)
            }
        }
    }

    private func compileRuleList(
        identifier: String,
        json: String,
        in store: WKContentRuleListStore
    ) async throws -> WKContentRuleList {
        guard let list = try await store.compileContentRuleList(
            forIdentifier: identifier,
            encodedContentRuleList: json
        ) else {
            throw AdBlockCompilerError.invalidAllowlistJSON
        }
        return list
    }
}
