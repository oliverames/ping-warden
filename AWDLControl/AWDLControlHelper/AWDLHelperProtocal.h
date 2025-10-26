//
//  AWDLHelperProtocol.h
//  AWDLControl
//
//  Defines the XPC protocol between the app and the privileged helper tool.
//  This allows the app to request privileged operations without password prompts.
//

#import <Foundation/Foundation.h>

// Protocol version - increment when making incompatible changes
#define kAWDLHelperProtocolVersion 1

// The protocol that the helper tool will implement
@protocol AWDLHelperProtocol

// Get the protocol version (for compatibility checking)
- (void)getVersionWithReply:(void(^)(NSString *version))reply;

// Load the AWDL monitoring daemon
- (void)loadDaemonWithReply:(void(^)(NSError *error))reply;

// Unload the AWDL monitoring daemon
- (void)unloadDaemonWithReply:(void(^)(NSError *error))reply;

// Check if daemon is currently loaded
- (void)isDaemonLoadedWithReply:(void(^)(BOOL loaded))reply;

@end

// The protocol that the app will use to communicate with the helper
@protocol AWDLHelperClientProtocol
// Currently no methods needed - helpers typically don't call back to app
@end
