// Objective-C++ only: the rule engine behind NFChromiumContentRuleList.

#import "NFChromiumContentRuleList.h"

#include <cstdint>
#include <memory>
#include <string>

namespace nf {

// Resource types as named in Safari content-blocker rules.
enum ResourceType : uint32_t {
    kResourceDocument = 1u << 0,
    kResourceImage = 1u << 1,
    kResourceStyleSheet = 1u << 2,
    kResourceScript = 1u << 3,
    kResourceFont = 1u << 4,
    kResourceRaw = 1u << 5,
    kResourceSVGDocument = 1u << 6,
    kResourceMedia = 1u << 7,
    kResourcePopup = 1u << 8,
    kResourcePing = 1u << 9,
    kResourceFetch = 1u << 10,
    kResourceWebSocket = 1u << 11,
    kResourceOther = 1u << 12,
};

// What rules are matched against: a request, or a frame's document when hiding elements.
struct ContentRequest {
    std::string url;
    std::string host;      // lowercase
    std::string topHost;   // lowercase host of the main document
    std::string frameURL;  // URL of the document the load belongs to
    std::string method;    // lowercase
    uint32_t types = kResourceOther;
    bool thirdParty = false;
    bool topFrame = true;
};

class ContentRuleSet;

// Whether the rules block the request. Rules apply in order, as in WebKit: a matching
// ignore-previous-rules cancels the blocks matched before it.
bool ShouldBlock(const ContentRuleSet &rules, const ContentRequest &request);

// CSS that hides the elements the rules hide in a document; empty when none apply.
std::string HidingStyleSheet(const ContentRuleSet &rules, const ContentRequest &document);

// Approximates the registrable domain: the last two labels, or three under common
// two-part suffixes such as co.uk and com.br.
std::string RegistrableDomain(const std::string &host);

}  // namespace nf

@interface NFChromiumContentRuleList (Internal)
- (std::shared_ptr<const nf::ContentRuleSet>)ruleSet;
@end
