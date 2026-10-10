import AppKit
import Foundation

/// Engine-specific data that has to travel back to the same engine to build the popup page.
protocol BrowserPopupEnginePayload {}

/// A page asked for a new window (`window.open`, `target=_blank`) that stays linked to its opener.
struct BrowserPopupRequest {
    let url: URL?
    let modifierFlags: NSEvent.ModifierFlags
    let enginePayload: BrowserPopupEnginePayload
}
