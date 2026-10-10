import AppKit

// CEF requires NSApp to be its NSApplication subclass, and SwiftUI ignores
// NSPrincipalClass, so the subclass is created before the SwiftUI app starts.
_ = NFChromiumApplication.shared
NFBrowserApp.main()
