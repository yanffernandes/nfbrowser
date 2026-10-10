#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// NSApplication subclass that CEF requires on macOS (CefAppProtocol).
/// It must become `NSApp` before SwiftUI creates the application; see App/main.swift.
@interface NFChromiumApplication : NSApplication
@end

NS_ASSUME_NONNULL_END
