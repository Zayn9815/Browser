import Foundation
import WebKit

public struct AdBlockManifest: Codable, Sendable, Equatable {
    public struct ShardDescriptor: Codable, Sendable, Equatable, Identifiable {
        public let identifier: String
        public let sourceList: String
        public let filename: String
        public let ruleCount: Int
        public let sha256: String

        public var id: String { identifier }

        public init(
            identifier: String,
            sourceList: String,
            filename: String,
            ruleCount: Int,
            sha256: String
        ) {
            self.identifier = identifier
            self.sourceList = sourceList
            self.filename = filename
            self.ruleCount = ruleCount
            self.sha256 = sha256
        }
    }

    public let bundleVersion: String
    public let generatedAtISO8601: String
    public let maxRulesPerShard: Int
    public let totalRuleCount: Int
    public let shards: [ShardDescriptor]

    public init(
        bundleVersion: String,
        generatedAtISO8601: String,
        maxRulesPerShard: Int,
        totalRuleCount: Int,
        shards: [ShardDescriptor]
    ) {
        self.bundleVersion = bundleVersion
        self.generatedAtISO8601 = generatedAtISO8601
        self.maxRulesPerShard = maxRulesPerShard
        self.totalRuleCount = totalRuleCount
        self.shards = shards
    }
}

@MainActor
public protocol AdBlockRuleProviding: AnyObject {
    var isReady: Bool { get }
    var compiledRuleLists: [WKContentRuleList] { get }
    func prepareRuleLists(allowlistedHosts: Set<String>) async throws -> [WKContentRuleList]
    func apply(to userContentController: WKUserContentController, siteHost: String?, allowlistedHosts: Set<String>) async
}

public enum AdBlockManifestLoader: Sendable {
    public static func loadBundledManifest(in bundle: Bundle = .main) -> AdBlockManifest? {
        guard let url = bundle.url(forResource: "manifest", withExtension: "json", subdirectory: "AdBlockShards"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(AdBlockManifest.self, from: data)
    }

    public static func summary(in bundle: Bundle = .main) -> String {
        guard let manifest = loadBundledManifest(in: bundle) else {
            return "AdBlockShards pending build generation"
        }
        return "\(manifest.shards.count) shards • \(manifest.totalRuleCount) rules (v\(manifest.bundleVersion))"
    }
}
