#import "NFChromiumContentRuleList+Internal.h"

#include <algorithm>
#include <cctype>
#include <cstring>
#include <mutex>
#include <regex>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace nf {

namespace {

enum class RuleAction : uint8_t { Block, HideElements, IgnorePrevious };

enum LoadType : uint8_t { kFirstParty = 1, kThirdParty = 2 };
enum LoadContext : uint8_t { kTopFrame = 1, kChildFrame = 2 };

std::string Lowercased(std::string value) {
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return value;
}

bool ContainsIgnoringCase(const std::string &text, const std::string &lowercaseNeedle) {
    return std::search(text.begin(), text.end(), lowercaseNeedle.begin(), lowercaseNeedle.end(), [](char a, char b) {
               return std::tolower(static_cast<unsigned char>(a)) == b;
           }) != text.end();
}

// Safari's domain lists: "*example.com" is the domain and its subdomains,
// "example.com" the domain alone.
bool DomainMatches(const std::string &pattern, const std::string &host) {
    if (pattern.empty() || pattern[0] != '*') {
        return host == pattern;
    }
    const size_t length = pattern.size() - 1;
    if (host.size() < length || host.compare(host.size() - length, length, pattern, 1, length) != 0) {
        return false;
    }
    return host.size() == length || host[host.size() - length - 1] == '.';
}

bool AnyDomainMatches(const std::vector<std::string> &patterns, const std::string &host) {
    return std::any_of(patterns.begin(), patterns.end(),
                       [&](const std::string &pattern) { return DomainMatches(pattern, host); });
}

bool AnyRegexMatches(const std::vector<std::regex> &regexes, const std::string &text) {
    return std::any_of(regexes.begin(), regexes.end(),
                       [&](const std::regex &regex) { return std::regex_search(text, regex); });
}

bool CompileRegex(const std::string &pattern, bool caseSensitive, std::regex &regex) {
    auto flags = std::regex::ECMAScript | std::regex::optimize;
    if (!caseSensitive) {
        flags |= std::regex::icase;
    }
    try {
        regex = std::regex(pattern, flags);
        return true;
    } catch (...) {
        return false;
    }
}

size_t SkipClass(const std::string &pattern, size_t i) {
    ++i;
    if (i < pattern.size() && pattern[i] == '^') {
        ++i;
    }
    while (i < pattern.size() && pattern[i] != ']') {
        i += pattern[i] == '\\' ? 2 : 1;
    }
    return std::min(i + 1, pattern.size());
}

// Returns npos for an unbalanced group.
size_t SkipGroup(const std::string &pattern, size_t i) {
    int depth = 0;
    while (i < pattern.size()) {
        const char c = pattern[i];
        if (c == '\\') {
            i += 2;
            continue;
        }
        if (c == '[') {
            i = SkipClass(pattern, i);
            continue;
        }
        if (c == '(') {
            ++depth;
        } else if (c == ')' && --depth == 0) {
            return i + 1;
        }
        ++i;
    }
    return std::string::npos;
}

size_t SkipQuantifier(const std::string &pattern, size_t i) {
    if (pattern[i] == '{') {
        const size_t close = pattern.find('}', i);
        i = close == std::string::npos ? pattern.size() : close + 1;
    } else {
        ++i;
    }
    if (i < pattern.size() && pattern[i] == '?') {
        ++i;
    }
    return i;
}

// The longest run of characters every URL the pattern matches contains, so a substring
// search can rule the pattern out before its regex runs. Empty when no run of three
// characters is certain.
std::string RequiredLiteral(const std::string &pattern) {
    std::string best;
    std::string run;
    auto endRun = [&] {
        if (run.size() > best.size()) {
            best = run;
        }
        run.clear();
    };
    size_t i = 0;
    while (i < pattern.size()) {
        const char c = pattern[i];
        bool isLiteral = false;
        char literal = 0;
        if (c == '\\') {
            if (i + 1 >= pattern.size()) {
                return "";
            }
            // \d, \w, \b and the like are classes or assertions, not characters.
            if (!std::isalnum(static_cast<unsigned char>(pattern[i + 1]))) {
                isLiteral = true;
                literal = pattern[i + 1];
            }
            i += 2;
        } else if (c == '[') {
            i = SkipClass(pattern, i);
        } else if (c == '(') {
            i = SkipGroup(pattern, i);
            if (i == std::string::npos) {
                return "";
            }
        } else if (c == '|') {
            // Alternation: no run is certain.
            return "";
        } else if (std::strchr("*+?{.^$", c) != nullptr) {
            ++i;
        } else {
            isLiteral = true;
            literal = c;
            ++i;
        }
        // The quantifier decides whether the token is certain to appear.
        const char quantifier = i < pattern.size() ? pattern[i] : '\0';
        if (quantifier == '*' || quantifier == '?' || quantifier == '{') {
            i = SkipQuantifier(pattern, i);
            endRun();
        } else if (quantifier == '+') {
            i = SkipQuantifier(pattern, i);
            if (isLiteral) {
                run += literal;
            }
            endRun();
        } else if (isLiteral) {
            run += literal;
        } else {
            endRun();
        }
    }
    endRun();
    return best.size() >= 3 ? best : "";
}

// For "||example.com^" patterns, the domain whose host and subdomains they match, so
// they are looked up by the request's host; empty for other patterns. Unlike WebKit,
// "example.com" then doesn't match "example.community", which the optional separator
// the converter writes for a trailing ^ lets through.
std::string AnchoredDomain(const std::string &pattern) {
    static const char *const kHostStarts[] = {"^[^:]+://+([^:/]+\\.)?", "^[htpsw]+:\\/\\/([a-z0-9-]+\\.)?"};
    // The host must end right after the domain: at a separator, port or path.
    static const char *const kHostEnds[] = {"[/:&?]", "[/:]", "([/:&?]", "([\\/:&\\?]", "\\/", "/", ":", "\\:"};
    for (const char *start : kHostStarts) {
        const size_t length = std::strlen(start);
        if (pattern.compare(0, length, start) != 0) {
            continue;
        }
        std::string domain;
        size_t i = length;
        while (i < pattern.size()) {
            const char c = pattern[i];
            if (std::isalnum(static_cast<unsigned char>(c)) || c == '-' || c == '_') {
                domain += static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
                ++i;
            } else if (c == '\\' && i + 1 < pattern.size() && pattern[i + 1] == '.') {
                domain += '.';
                i += 2;
            } else {
                break;
            }
        }
        if (domain.empty() || domain.front() == '.' || domain.back() == '.') {
            return "";
        }
        for (const char *end : kHostEnds) {
            if (pattern.compare(i, std::strlen(end), end) == 0) {
                return domain;
            }
        }
        return "";
    }
    return "";
}

}  // namespace

struct ContentRule {
    RuleAction action = RuleAction::Block;
    std::string selector;
    std::string css;  // the hiding rule for the selector
    std::string urlFilter;
    bool caseSensitive = false;
    bool matchesEveryURL = false;
    // Cheap checks a match requires: the host's domain ("*example.com") and a lowercase
    // substring of the URL.
    std::string hostDomain;
    std::string literal;
    uint32_t types = 0;
    uint8_t loadTypes = 0;
    uint8_t loadContexts = 0;
    std::string method;
    std::vector<std::string> ifDomain;
    std::vector<std::string> unlessDomain;
    std::vector<std::string> ifFrameURL;
    std::vector<std::string> unlessFrameURL;

    // Regexes compile on first use: most rules are ruled out before that.
    mutable std::once_flag compileOnce;
    mutable std::regex urlRegex;
    mutable std::vector<std::regex> ifFrameRegexes;
    mutable std::vector<std::regex> unlessFrameRegexes;
    mutable bool usable = true;

    void Compile() const {
        std::call_once(compileOnce, [this] {
            if (!matchesEveryURL && !CompileRegex(urlFilter, caseSensitive, urlRegex)) {
                usable = false;
                return;
            }
            for (auto [patterns, regexes] : {std::pair{&ifFrameURL, &ifFrameRegexes},
                                             std::pair{&unlessFrameURL, &unlessFrameRegexes}}) {
                for (const std::string &pattern : *patterns) {
                    std::regex regex;
                    if (!CompileRegex(pattern, caseSensitive, regex)) {
                        usable = false;
                        return;
                    }
                    regexes->push_back(std::move(regex));
                }
            }
        });
    }

    // Matches every load and document, whatever the page.
    bool IsUnconditional() const {
        return matchesEveryURL && types == 0 && loadTypes == 0 && loadContexts == 0 && method.empty() &&
               ifDomain.empty() && unlessDomain.empty() && ifFrameURL.empty() && unlessFrameURL.empty();
    }

    bool Matches(const ContentRequest &request) const {
        if ((types != 0 && (types & request.types) == 0) ||
            (loadTypes != 0 && (loadTypes & (request.thirdParty ? kThirdParty : kFirstParty)) == 0) ||
            (loadContexts != 0 && (loadContexts & (request.topFrame ? kTopFrame : kChildFrame)) == 0) ||
            (!method.empty() && method != request.method) ||
            (!ifDomain.empty() && !AnyDomainMatches(ifDomain, request.topHost)) ||
            (!unlessDomain.empty() && AnyDomainMatches(unlessDomain, request.topHost)) ||
            (!hostDomain.empty() && !DomainMatches(hostDomain, request.host)) ||
            (!literal.empty() && !ContainsIgnoringCase(request.url, literal))) {
            return false;
        }
        Compile();
        if (!usable || (!ifFrameRegexes.empty() && !AnyRegexMatches(ifFrameRegexes, request.frameURL)) ||
            (!unlessFrameRegexes.empty() && AnyRegexMatches(unlessFrameRegexes, request.frameURL))) {
            return false;
        }
        return matchesEveryURL || std::regex_search(request.url, urlRegex);
    }
};

class ContentRuleSet {
   public:
    void Add(std::unique_ptr<ContentRule> rule) { rules_.push_back(std::move(rule)); }

    // Network rules are found by the request's host, by a substring of its URL, or are
    // checked for every request when neither applies. Hiding rules that apply to every
    // page share one prepared stylesheet; the other hiding rules, and the exceptions that
    // can cancel them, are found by the page's domain or the document's host.
    void Index() {
        for (uint32_t index = 0; index < rules_.size(); ++index) {
            ContentRule &rule = *rules_[index];
            if (rule.action == RuleAction::HideElements) {
                // :is() takes a forgiving selector list, so a selector Chromium doesn't
                // support doesn't drop the others listed with it.
                rule.css = ":is(" + rule.selector + "){display:none!important}\n";
            }
            const bool appliesToDocuments = rule.action == RuleAction::HideElements ||
                                            (rule.action == RuleAction::IgnorePrevious &&
                                             (rule.types == 0 || (rule.types & kResourceDocument) != 0));
            if (appliesToDocuments && rule.action == RuleAction::HideElements && rule.IsUnconditional()) {
                everyPageHiding_.push_back(index);
                everyPageCSS_ += rule.css;
            } else if (appliesToDocuments && !rule.ifDomain.empty()) {
                for (const std::string &domain : rule.ifDomain) {
                    documentRulesByPageDomain_[domain[0] == '*' ? domain.substr(1) : domain].push_back(index);
                }
            } else if (appliesToDocuments && !rule.hostDomain.empty()) {
                documentRulesByHost_[rule.hostDomain.substr(1)].push_back(index);
            } else if (appliesToDocuments) {
                otherDocumentRules_.push_back(index);
            }
            if (rule.action == RuleAction::HideElements) {
                continue;
            }
            if (!rule.hostDomain.empty()) {
                rulesByDomain_[rule.hostDomain.substr(1)].push_back(index);
            } else if (!rule.literal.empty()) {
                rulesByLiteral_[LiteralKey(rule.literal, 0)].push_back(index);
            } else {
                unindexedRules_.push_back(index);
            }
        }
    }

    bool ShouldBlock(const ContentRequest &request) const {
        std::vector<uint32_t> candidates;
        AddRulesForDomains(rulesByDomain_, request.host, candidates);
        if (!rulesByLiteral_.empty()) {
            const std::string url = Lowercased(request.url);
            for (size_t position = 0; position + 3 <= url.size(); ++position) {
                auto found = rulesByLiteral_.find(LiteralKey(url, position));
                if (found == rulesByLiteral_.end()) {
                    continue;
                }
                for (uint32_t index : found->second) {
                    const std::string &literal = rules_[index]->literal;
                    if (url.compare(position, literal.size(), literal) == 0) {
                        candidates.push_back(index);
                    }
                }
            }
        }
        candidates.insert(candidates.end(), unindexedRules_.begin(), unindexedRules_.end());
        std::sort(candidates.begin(), candidates.end());
        candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());

        bool blocked = false;
        for (uint32_t index : candidates) {
            const ContentRule &rule = *rules_[index];
            // A block while blocked, or an exception while not, changes nothing.
            if ((rule.action == RuleAction::Block) != blocked && rule.Matches(request)) {
                blocked = rule.action == RuleAction::Block;
            }
        }
        return blocked;
    }

    std::string HidingStyleSheet(const ContentRequest &document) const {
        std::vector<uint32_t> candidates = otherDocumentRules_;
        AddRulesForDomains(documentRulesByPageDomain_, document.topHost, candidates);
        AddRulesForDomains(documentRulesByHost_, document.host, candidates);
        std::sort(candidates.begin(), candidates.end());
        candidates.erase(std::unique(candidates.begin(), candidates.end()), candidates.end());

        // An exception drops the hiding matched before it, every-page rules included.
        std::vector<uint32_t> matched;
        int64_t lastException = -1;
        for (uint32_t index : candidates) {
            const ContentRule &rule = *rules_[index];
            if (!rule.Matches(document)) {
                continue;
            }
            if (rule.action == RuleAction::IgnorePrevious) {
                matched.clear();
                lastException = index;
            } else {
                matched.push_back(index);
            }
        }
        std::string css;
        if (lastException < 0) {
            css = everyPageCSS_;
        } else {
            for (uint32_t index : everyPageHiding_) {
                if (index > lastException) {
                    css += rules_[index]->css;
                }
            }
        }
        for (uint32_t index : matched) {
            css += rules_[index]->css;
        }
        return css;
    }

    size_t size() const { return rules_.size(); }

   private:
    using RulesByDomain = std::unordered_map<std::string, std::vector<uint32_t>>;

    // Adds the rules filed under `host` or any domain it belongs to.
    static void AddRulesForDomains(const RulesByDomain &rulesByDomain,
                                   const std::string &host,
                                   std::vector<uint32_t> &rules) {
        for (size_t start = 0; start != std::string::npos;) {
            auto found = rulesByDomain.find(host.substr(start));
            if (found != rulesByDomain.end()) {
                rules.insert(rules.end(), found->second.begin(), found->second.end());
            }
            const size_t dot = host.find('.', start);
            start = dot == std::string::npos ? std::string::npos : dot + 1;
        }
    }

    static uint32_t LiteralKey(const std::string &text, size_t position) {
        return static_cast<uint32_t>(static_cast<unsigned char>(text[position])) |
               static_cast<uint32_t>(static_cast<unsigned char>(text[position + 1])) << 8 |
               static_cast<uint32_t>(static_cast<unsigned char>(text[position + 2])) << 16;
    }

    std::vector<std::unique_ptr<ContentRule>> rules_;
    RulesByDomain rulesByDomain_;
    std::unordered_map<uint32_t, std::vector<uint32_t>> rulesByLiteral_;
    std::vector<uint32_t> unindexedRules_;
    std::vector<uint32_t> everyPageHiding_;
    std::string everyPageCSS_;
    RulesByDomain documentRulesByPageDomain_;
    RulesByDomain documentRulesByHost_;
    std::vector<uint32_t> otherDocumentRules_;
};

bool ShouldBlock(const ContentRuleSet &rules, const ContentRequest &request) {
    return rules.ShouldBlock(request);
}

std::string HidingStyleSheet(const ContentRuleSet &rules, const ContentRequest &document) {
    return rules.HidingStyleSheet(document);
}

std::string RegistrableDomain(const std::string &host) {
    std::vector<std::string> labels;
    size_t start = 0;
    while (true) {
        const size_t dot = host.find('.', start);
        labels.push_back(host.substr(start, dot == std::string::npos ? std::string::npos : dot - start));
        if (dot == std::string::npos) {
            break;
        }
        start = dot + 1;
    }
    if (labels.size() <= 2) {
        return host;
    }
    const std::string &secondLevel = labels[labels.size() - 2];
    static const std::unordered_set<std::string> kSecondLevel = {"co", "com", "net", "org", "gov", "edu", "ac"};
    const size_t keep = labels.back().size() == 2 && kSecondLevel.count(secondLevel) > 0 ? 3 : 2;
    std::string result;
    for (size_t i = labels.size() - keep; i < labels.size(); ++i) {
        result += (result.empty() ? "" : ".") + labels[i];
    }
    return result;
}

}  // namespace nf

#pragma mark - Parsing

static std::vector<std::string> NFStrings(id value, bool lowercase) {
    std::vector<std::string> strings;
    if (![value isKindOfClass:NSArray.class]) {
        return strings;
    }
    for (NSString *item in (NSArray *)value) {
        if ([item isKindOfClass:NSString.class] && item.length > 0) {
            std::string string = item.UTF8String;
            strings.push_back(lowercase ? nf::Lowercased(string) : string);
        }
    }
    return strings;
}

// ORs the bits of the names listed in `value`. False when the trigger lists only names
// Chromium has no equivalent for, so the rule can't apply.
template <typename Bits>
static bool NFParseFlags(id value, NSDictionary<NSString *, NSNumber *> *bitsByName, Bits &bits) {
    if (value == nil) {
        return true;
    }
    for (const std::string &name : NFStrings(value, false)) {
        bits |= static_cast<Bits>([bitsByName[@(name.c_str())] unsignedIntValue]);
    }
    return bits != 0;
}

static NSDictionary<NSString *, NSNumber *> *NFResourceTypesByName() {
    static NSDictionary<NSString *, NSNumber *> *const types = @{
        @"document" : @(nf::kResourceDocument),
        @"image" : @(nf::kResourceImage),
        @"style-sheet" : @(nf::kResourceStyleSheet),
        @"script" : @(nf::kResourceScript),
        @"font" : @(nf::kResourceFont),
        @"raw" : @(nf::kResourceRaw),
        @"svg-document" : @(nf::kResourceSVGDocument),
        @"media" : @(nf::kResourceMedia),
        @"popup" : @(nf::kResourcePopup),
        @"ping" : @(nf::kResourcePing),
        @"fetch" : @(nf::kResourceFetch),
        @"websocket" : @(nf::kResourceWebSocket),
        @"other" : @(nf::kResourceOther),
    };
    return types;
}

// A request from a top-level page, as the view builds one.
static nf::ContentRequest NFTopFrameRequest(NSURL *url, uint32_t types, NSURL *pageURL) {
    nf::ContentRequest request;
    request.url = url.absoluteString.UTF8String ?: "";
    request.host = nf::Lowercased(url.host.UTF8String ?: "");
    request.topHost = nf::Lowercased(pageURL.host.UTF8String ?: "");
    request.frameURL = (types & nf::kResourceDocument) != 0 ? request.url : pageURL.absoluteString.UTF8String ?: "";
    request.method = "get";
    request.types = types;
    request.thirdParty = nf::RegistrableDomain(request.host) != nf::RegistrableDomain(request.topHost);
    request.topFrame = true;
    return request;
}

// One entry of a Safari content-blocker list; nullptr for entries Chromium can't apply:
// actions other than block, css-display-none and ignore-previous-rules (the filter-list
// converter emits no others), or triggers on the top-level URL.
static std::unique_ptr<nf::ContentRule> NFParseRule(id entry) {
    NSDictionary *trigger = [entry isKindOfClass:NSDictionary.class] ? entry[@"trigger"] : nil;
    NSDictionary *action = [entry isKindOfClass:NSDictionary.class] ? entry[@"action"] : nil;
    if (![trigger isKindOfClass:NSDictionary.class] || ![action isKindOfClass:NSDictionary.class]) {
        return nullptr;
    }
    NSString *urlFilter = trigger[@"url-filter"];
    NSString *type = action[@"type"];
    if (![urlFilter isKindOfClass:NSString.class] || urlFilter.length == 0 || ![type isKindOfClass:NSString.class] ||
        trigger[@"if-top-url"] != nil || trigger[@"unless-top-url"] != nil) {
        return nullptr;
    }

    auto rule = std::make_unique<nf::ContentRule>();
    if ([type isEqualToString:@"block"]) {
        rule->action = nf::RuleAction::Block;
    } else if ([type isEqualToString:@"ignore-previous-rules"]) {
        rule->action = nf::RuleAction::IgnorePrevious;
    } else if ([type isEqualToString:@"css-display-none"]) {
        NSString *selector = action[@"selector"];
        // Braces would end the hiding rule early and inject CSS of their own.
        if (![selector isKindOfClass:NSString.class] || selector.length == 0 ||
            [selector rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"{}"]].location !=
                NSNotFound) {
            return nullptr;
        }
        rule->action = nf::RuleAction::HideElements;
        rule->selector = selector.UTF8String;
    } else {
        return nullptr;
    }

    static NSDictionary<NSString *, NSNumber *> *const kLoadTypes =
        @{@"first-party" : @(nf::kFirstParty), @"third-party" : @(nf::kThirdParty)};
    static NSDictionary<NSString *, NSNumber *> *const kLoadContexts =
        @{@"top-frame" : @(nf::kTopFrame), @"child-frame" : @(nf::kChildFrame)};
    if (!NFParseFlags(trigger[@"resource-type"], NFResourceTypesByName(), rule->types) ||
        !NFParseFlags(trigger[@"load-type"], kLoadTypes, rule->loadTypes) ||
        !NFParseFlags(trigger[@"load-context"], kLoadContexts, rule->loadContexts)) {
        return nullptr;
    }

    rule->urlFilter = urlFilter.UTF8String;
    rule->caseSensitive = [trigger[@"url-filter-is-case-sensitive"] boolValue];
    rule->matchesEveryURL = rule->urlFilter == ".*";
    if (!rule->matchesEveryURL) {
        rule->literal = nf::Lowercased(nf::RequiredLiteral(rule->urlFilter));
        const std::string domain = nf::AnchoredDomain(rule->urlFilter);
        if (!domain.empty()) {
            rule->hostDomain = "*" + domain;
        }
    }
    NSString *method = trigger[@"request-method"];
    if ([method isKindOfClass:NSString.class]) {
        rule->method = nf::Lowercased(method.UTF8String);
    }
    rule->ifDomain = NFStrings(trigger[@"if-domain"], true);
    rule->unlessDomain = NFStrings(trigger[@"unless-domain"], true);
    rule->ifFrameURL = NFStrings(trigger[@"if-frame-url"], false);
    rule->unlessFrameURL = NFStrings(trigger[@"unless-frame-url"], false);
    return rule;
}

#pragma mark - NFChromiumContentRuleList

@implementation NFChromiumContentRuleList {
    std::shared_ptr<const nf::ContentRuleSet> _ruleSet;
}

// Compiled lists by identifier, for as long as a view holds them.
+ (NSMapTable<NSString *, NFChromiumContentRuleList *> *)compiledLists {
    static NSMapTable *lists;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      lists = [NSMapTable strongToWeakObjectsMapTable];
    });
    return lists;
}

+ (instancetype)ruleListWithIdentifier:(NSString *)identifier loadJSON:(NSString *_Nullable (^)(void))loadJSON {
    NSMapTable<NSString *, NFChromiumContentRuleList *> *compiled = [self compiledLists];
    @synchronized(compiled) {
        NFChromiumContentRuleList *list = [compiled objectForKey:identifier];
        if (list) {
            return list;
        }
    }

    NFChromiumContentRuleList *list = nil;
    @autoreleasepool {
        NSData *data = [loadJSON() dataUsingEncoding:NSUTF8StringEncoding];
        NSArray *entries = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![entries isKindOfClass:NSArray.class]) {
            return nil;
        }
        auto ruleSet = std::make_shared<nf::ContentRuleSet>();
        for (id entry in entries) {
            if (auto rule = NFParseRule(entry)) {
                ruleSet->Add(std::move(rule));
            }
        }
        ruleSet->Index();
        list = [[self alloc] initWithIdentifier:identifier ruleSet:ruleSet];
    }

    @synchronized(compiled) {
        // Another thread may have compiled the same list meanwhile.
        NFChromiumContentRuleList *existing = [compiled objectForKey:identifier];
        if (existing) {
            return existing;
        }
        [compiled setObject:list forKey:identifier];
    }
    return list;
}

- (instancetype)initWithIdentifier:(NSString *)identifier ruleSet:(std::shared_ptr<const nf::ContentRuleSet>)ruleSet {
    self = [super init];
    if (self) {
        _identifier = [identifier copy];
        _ruleSet = std::move(ruleSet);
    }
    return self;
}

- (NSUInteger)ruleCount {
    return _ruleSet->size();
}

- (BOOL)blocksURL:(NSURL *)url resourceType:(NSString *)resourceType pageURL:(NSURL *)pageURL {
    const uint32_t types = NFResourceTypesByName()[resourceType].unsignedIntValue ?: nf::kResourceOther;
    return nf::ShouldBlock(*_ruleSet, NFTopFrameRequest(url, types, pageURL));
}

- (NSString *)hidingStyleSheetForPageURL:(NSURL *)pageURL {
    const std::string css = nf::HidingStyleSheet(*_ruleSet, NFTopFrameRequest(pageURL, nf::kResourceDocument, pageURL));
    return @(css.c_str());
}

- (std::shared_ptr<const nf::ContentRuleSet>)ruleSet {
    return _ruleSet;
}

@end
