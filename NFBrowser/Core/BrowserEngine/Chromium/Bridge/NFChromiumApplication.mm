#import "NFChromiumApplication.h"

#include "include/cef_application_mac.h"

@interface NFChromiumApplication () <CefAppProtocol>
@end

@implementation NFChromiumApplication {
    BOOL _handlingSendEvent;
}

- (BOOL)isHandlingSendEvent {
    return _handlingSendEvent;
}

- (void)setHandlingSendEvent:(BOOL)handlingSendEvent {
    _handlingSendEvent = handlingSendEvent;
}

- (void)sendEvent:(NSEvent *)event {
    CefScopedSendingEvent sendingEventScoper;
    [super sendEvent:event];
}

@end
