import Foundation
@testable import NFBrowser
import Testing

/// Filter lists as Chromium Spaces apply them: Safari content-blocker JSON, with
/// WebKit's semantics.
struct ChromiumContentRuleListTests {
    private let news = "https://news.site/"

    private func url(_ string: String) throws -> URL {
        try #require(URL(string: string))
    }

    private func ruleList(_ rules: [[String: Any]]) throws -> NFChromiumContentRuleList {
        let json = try #require(String(bytes: JSONSerialization.data(withJSONObject: rules), encoding: .utf8))
        return try #require(NFChromiumContentRuleList(identifier: UUID().uuidString) { json })
    }

    private func rule(_ trigger: [String: Any], _ action: [String: Any] = ["type": "block"]) -> [String: Any] {
        ["trigger": trigger, "action": action]
    }

    private func blocks(
        _ lists: [NFChromiumContentRuleList],
        _ resource: String,
        type: String = "script",
        page: String? = nil
    ) throws -> Bool {
        let resourceURL = try url(resource)
        let pageURL = try url(page ?? news)
        return lists.contains { $0.blocks(resourceURL, resourceType: type, pageURL: pageURL) }
    }

    private func hiding(_ lists: [NFChromiumContentRuleList], page: String) throws -> String {
        let pageURL = try url(page)
        return lists.map { $0.hidingStyleSheet(forPageURL: pageURL) }.joined()
    }

    @Test func domainAnchorCoversSubdomainsButNotLookalikes() throws {
        let list = try [ruleList([
            rule(["url-filter": "^[^:]+://+([^:/]+\\.)?ads\\.example\\.com[/:&?]?", "load-type": ["third-party"]])
        ])]
        #expect(try blocks(list, "https://ads.example.com/a.js"))
        #expect(try blocks(list, "https://cdn.eu.ads.example.com/a.js"))
        #expect(try !blocks(list, "https://ads.example.community/a.js"))
        #expect(try !blocks(list, "https://example.com/a.js"))
        // First party on example.com's own pages.
        #expect(try !blocks(list, "https://ads.example.com/a.js", page: "https://www.example.com/"))
    }

    @Test func rulesApplyInOrder() throws {
        let list = try [ruleList([
            rule(["url-filter": "ad\\.js"]),
            rule(["url-filter": "ad\\.js", "if-domain": ["*friendly.org"]], ["type": "ignore-previous-rules"]),
            rule(["url-filter": "ad\\.js", "resource-type": ["image"]])
        ])]
        let friendly = "https://www.friendly.org/"
        #expect(try blocks(list, "https://cdn.net/ad.js"))
        #expect(try !blocks(list, "https://cdn.net/ad.js", page: friendly))
        #expect(try blocks(list, "https://cdn.net/ad.js", type: "image", page: friendly))
    }

    @Test func literalPrefilterKeepsRegexSemantics() throws {
        let list = try [ruleList([rule(["url-filter": "\\/banners?\\/[0-9]+x[0-9]+\\.", "resource-type": ["image"]])])]
        #expect(try blocks(list, "https://x.com/banner/300x250.png", type: "image"))
        #expect(try blocks(list, "https://x.com/banners/728x90.gif", type: "image"))
        #expect(try !blocks(list, "https://x.com/banner/top.png", type: "image"))
        #expect(try !blocks(list, "https://x.com/banner/300x250.png", type: "script"))
    }

    @Test func caseSensitivityFollowsTheTrigger() throws {
        let sensitive = try [ruleList([rule(["url-filter": "AdServe", "url-filter-is-case-sensitive": true])])]
        let insensitive = try [ruleList([rule(["url-filter": "AdServe"])])]
        #expect(try blocks(sensitive, "https://x.com/AdServe/1"))
        #expect(try !blocks(sensitive, "https://x.com/adserve/1"))
        #expect(try blocks(insensitive, "https://x.com/adserve/1"))
    }

    @Test func pageDomainsLimitRules() throws {
        let list = try [ruleList([
            rule(["url-filter": ".*", "if-domain": ["*social.example"], "resource-type": ["script"]]),
            rule(["url-filter": "track", "unless-domain": ["*good.com"]])
        ])]
        #expect(try blocks(list, "https://cdn.net/app.js", page: "https://www.social.example/"))
        #expect(try !blocks(list, "https://cdn.net/app.js"))
        #expect(try blocks(list, "https://cdn.net/track.gif", type: "image"))
        #expect(try !blocks(list, "https://cdn.net/track.gif", type: "image", page: "https://good.com/"))
    }

    @Test func hidingFollowsDomainsAndExceptions() throws {
        let list = try [ruleList([
            rule(["url-filter": ".*"], ["type": "css-display-none", "selector": ".ad"]),
            rule(["url-filter": ".*", "if-domain": ["*shop.com"]], ["type": "css-display-none", "selector": ".promo"]),
            rule(
                ["url-filter": ".*", "if-domain": ["*clean.org"], "resource-type": ["document"]],
                ["type": "ignore-previous-rules"]
            ),
            rule(["url-filter": ".*"], ["type": "css-display-none", "selector": ".late"])
        ])]
        let newsCSS = try hiding(list, page: news)
        #expect(newsCSS.contains(":is(.ad){display:none!important}"))
        #expect(newsCSS.contains(".late") && !newsCSS.contains(".promo"))
        #expect(try hiding(list, page: "https://shop.com/").contains(".promo"))
        let cleanCSS = try hiding(list, page: "https://clean.org/")
        #expect(cleanCSS.contains(".late") && !cleanCSS.contains(".ad)"))
    }

    @Test func leavesOutWhatChromiumCannotApply() throws {
        let list = try ruleList([
            rule(["url-filter": ".*"], ["type": "block-cookies"]),
            rule(["url-filter": ".*"], ["type": "css-display-none", "selector": "a{} body"]),
            rule(["url-filter": ".*", "if-top-url": ["x"]]),
            rule(["url-filter": ".*", "resource-type": ["unknown-type"]]),
            rule(["url-filter": "(unclosed"])
        ])
        // Only the rule with the broken regex parses; it never matches.
        #expect(list.ruleCount == 1)
        #expect(try !blocks([list], "https://x.com/(unclosed"))
        #expect(try hiding([list], page: news).isEmpty)
    }

    @Test func understandsTheFilterListConverter() throws {
        let filters = """
        ||ads.example.com^$third-party
        @@||cdn.ads.example.com^
        /banner/*/img^
        ##.ad-slot
        example.org##.sponsored
        """
        let record = FilterListRecord(
            id: "test",
            name: "Test",
            summary: "",
            sourceKind: .custom,
            sourceURL: "",
            isRecommended: false,
            enabledByDefault: false
        )
        let shards = try ContentBlockerCompileService().compile(record: record, rawText: filters).jsonShards
        let lists = shards.compactMap { json in NFChromiumContentRuleList(identifier: UUID().uuidString) { json } }
        try #require(lists.count == shards.count && !lists.isEmpty)
        #expect(try blocks(lists, "https://ads.example.com/a.js"))
        #expect(try !blocks(lists, "https://cdn.ads.example.com/a.js"))
        // In filter syntax ^ is a separator, which "." is not.
        #expect(try blocks(lists, "https://x.com/banner/123/img?size=300", type: "image"))
        #expect(try !blocks(lists, "https://x.com/banner/123/img.png", type: "image"))
        #expect(try !blocks(lists, "https://x.com/app.js"))
        #expect(try hiding(lists, page: news).contains(".ad-slot"))
        #expect(try !hiding(lists, page: news).contains(".sponsored"))
        #expect(try hiding(lists, page: "https://www.example.org/").contains(".sponsored"))
    }
}
