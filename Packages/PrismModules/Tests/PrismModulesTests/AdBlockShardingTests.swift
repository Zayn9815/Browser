import Foundation
import Testing
@testable import AdBlockEngine

@Suite("AdBlockEngine Sharding & Allowlist Verification")
struct AdBlockShardingTests {
    @Test("AdBlockManifest decodes valid sharded EasyList + EasyPrivacy JSON cleanly")
    func manifestDecoding() throws {
        let json = """
        {
          "bundleVersion": "a1b2c3d4e5f60001",
          "generatedAtISO8601": "2026-11-24T00:00:00Z",
          "maxRulesPerShard": 125000,
          "totalRuleCount": 131776,
          "shards": [
            {
              "identifier": "easylist_shard_0_deadbeef1234",
              "sourceList": "easylist",
              "filename": "easylist_shard_0.json",
              "ruleCount": 78420,
              "sha256": "deadbeef1234567890"
            },
            {
              "identifier": "easyprivacy_shard_0_cafebabe5678",
              "sourceList": "easyprivacy",
              "filename": "easyprivacy_shard_0.json",
              "ruleCount": 53356,
              "sha256": "cafebabe5678901234"
            }
          ]
        }
        """
        let manifest = try JSONDecoder().decode(AdBlockManifest.self, from: Data(json.utf8))
        #expect(manifest.shards.count == 2)
        #expect(manifest.maxRulesPerShard == 125_000)
        #expect(manifest.totalRuleCount == 131_776)
        try AdBlockRuleCompiler.validateManifest(manifest)
    }

    @Test("AdBlockRuleCompiler rejects any shard exceeding WebKit's 150,000 rule ceiling")
    func enforcesRuleCeiling() {
        let oversizedManifest = AdBlockManifest(
            bundleVersion: "bad",
            generatedAtISO8601: "2026-11-24T00:00:00Z",
            maxRulesPerShard: 125_000,
            totalRuleCount: 150_001,
            shards: [
                .init(
                    identifier: "oversized_shard_0",
                    sourceList: "easylist",
                    filename: "oversized_shard_0.json",
                    ruleCount: 150_001,
                    sha256: "0000"
                ),
            ]
        )

        #expect(throws: AdBlockCompilerError.self) {
            try AdBlockRuleCompiler.validateManifest(oversizedManifest)
        }
    }

    @Test("Per-site allowlist generates valid ignore-previous-rules WebKit JSON")
    func perSiteAllowlistGeneration() throws {
        let json = try AdBlockRuleCompiler.makeAllowlistJSON(for: ["Example.COM", "news.ycombinator.com", "  "])
        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rules.count == 1)

        let action = try #require(rules[0]["action"] as? [String: Any])
        #expect(action["type"] as? String == "ignore-previous-rules")

        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        #expect(trigger["url-filter"] as? String == ".*")
        let domains = try #require(trigger["if-domain"] as? [String])
        #expect(domains == ["*example.com", "*news.ycombinator.com"])
    }

    @Test("Empty allowlist returns empty JSON rule array")
    func emptyAllowlistReturnsEmptyArray() throws {
        let json = try AdBlockRuleCompiler.makeAllowlistJSON(for: [])
        #expect(json == "[]")
    }
}
