//
//  HelperProtocol.h
//  PingWarden
//
//  XPC protocol for communication between main app and privileged helper daemon.
//  Based on james-howard/AWDLControl SMAppService architecture.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

#import <Foundation/Foundation.h>

/// XPC protocol for AWDL control between main app and helper daemon.
/// The helper runs as a LaunchDaemon registered via SMAppService and controls the AWDL interface.
@protocol PingWardenHelperProtocol <NSObject>

/// Check if AWDL is currently enabled (interface can come UP)
/// @param reply Callback with current enabled state
- (void)isAWDLEnabledWithReply:(void (^_Nonnull)(BOOL enabled))reply NS_SWIFT_NAME(isAWDLEnabled(reply:));

/// Enable or disable AWDL interface monitoring
/// @param enable YES to allow AWDL (stop blocking), NO to block AWDL (keep interface DOWN)
/// @param reply Callback with success status
- (void)setAWDLEnabled:(BOOL)enable withReply:(void (^_Nonnull)(BOOL success))reply NS_SWIFT_NAME(setAWDLEnabled(_:reply:));

/// Get current AWDL interface status for diagnostics
/// @param reply Callback with human-readable status string
- (void)getAWDLStatusWithReply:(void (^_Nonnull)(NSString *_Nonnull status))reply NS_SWIFT_NAME(getAWDLStatus(reply:));

/// Get the helper daemon version
/// @param reply Callback with version string
- (void)getVersionWithReply:(void (^_Nonnull)(NSString *_Nonnull version))reply NS_SWIFT_NAME(getVersion(reply:));

/// Get the number of attempts to turn off AWDL, including failed writes.
/// @param reply Callback with intervention count
- (void)getAWDLInterventionCountWithReply:(void (^_Nonnull)(NSInteger count))reply NS_SWIFT_NAME(getAWDLInterventionCount(reply:));

/// Reset the AWDL intervention counter to zero
/// @param reply Callback with success status
- (void)resetAWDLInterventionCountWithReply:(void (^_Nonnull)(BOOL success))reply NS_SWIFT_NAME(resetAWDLInterventionCount(reply:));

@end

#if defined(PINGWARDEN_MIGRATION_HELPER) && PINGWARDEN_MIGRATION_HELPER

/// Additive receiver protocol. The original six selectors above are unchanged.
/// No receiver principal is admitted by the current helper build.
typedef NS_ENUM(NSInteger, PWReceiverResult) {
    PWReceiverResultOK = 0,
    PWReceiverResultUnsupportedPrincipal = 1,
    PWReceiverResultUnavailable = 2,
    PWReceiverResultLegacyBusy = 3,
    PWReceiverResultLegacyGrace = 4,
    PWReceiverResultAlreadyOwned = 5,
    PWReceiverResultStaleOwnership = 6,
    PWReceiverResultRestorationUncertain = 7,
    PWReceiverResultOperationFailed = 8
};

@protocol PingWardenReceiverProtocol <PingWardenHelperProtocol>
- (void)receiverStatusWithReply:(void (^_Nonnull)(PWReceiverResult result,
    NSInteger protocolVersion, NSUUID *_Nullable epoch, NSUUID *_Nullable generation))reply;

- (void)acquireReceiverOwnershipForEpoch:(NSUUID *_Nonnull)epoch
    importGeneration:(NSUUID *_Nonnull)importGeneration
    reply:(void (^_Nonnull)(PWReceiverResult result, NSUUID *_Nullable token,
                           NSUUID *_Nullable generation))reply;

- (void)setReceiverAWDLEnabled:(BOOL)enabled epoch:(NSUUID *_Nonnull)epoch
    token:(NSUUID *_Nonnull)token
    reply:(void (^_Nonnull)(PWReceiverResult result, unsigned long long commandSequence))reply;

- (void)releaseReceiverOwnershipForEpoch:(NSUUID *_Nonnull)epoch
    token:(NSUUID *_Nonnull)token reply:(void (^_Nonnull)(PWReceiverResult result))reply;
@end
#endif
