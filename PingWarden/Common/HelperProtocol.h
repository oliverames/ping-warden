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

/// Get the number of AWDL interventions (how many times AWDL was blocked from coming up)
/// @param reply Callback with intervention count
- (void)getAWDLInterventionCountWithReply:(void (^_Nonnull)(NSInteger count))reply NS_SWIFT_NAME(getAWDLInterventionCount(reply:));

/// Reset the AWDL intervention counter to zero
/// @param reply Callback with success status
- (void)resetAWDLInterventionCountWithReply:(void (^_Nonnull)(BOOL success))reply NS_SWIFT_NAME(resetAWDLInterventionCount(reply:));

@end
