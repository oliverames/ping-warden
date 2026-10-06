//
//  PingWardenMonitor.h
//  PingWardenHelper
//
//  Monitors AWDL interface state using AF_ROUTE socket.
//  Based on james-howard/AWDLControl and jamestut/awdlkiller.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

#import <Foundation/Foundation.h>
#import <os/log.h>

NS_ASSUME_NONNULL_BEGIN

/// Shared log handle for the helper, under the app's subsystem so one
/// `log show` predicate covers both processes.
os_log_t PingWardenHelperLog(void);

/// Monitors and controls the AWDL (awdl0) network interface.
/// While awdlEnabled is NO, the monitor keeps awdl0 down: every AF_ROUTE
/// wakeup and a periodic timeout re-read the interface's actual flags, so a
/// route message the kernel dropped cannot leave awdl0 up.
@interface PingWardenMonitor : NSObject

/// When YES, AWDL is allowed to be up (normal operation).
/// When NO, AWDL is kept down (blocking mode).
/// Reading reports blocking only while the monitor is running and the
/// interface can be confirmed DOWN. Unknown/unavailable state returns YES.
@property (nonatomic, readonly) BOOL awdlEnabled;

/// Set the AWDL enabled state. Returns YES only after the interface flags
/// confirm the change, NO if the operation fails or the monitor has stopped.
/// Allowing AWDL works even if the poll thread has died; blocking needs it.
- (BOOL)setAwdlEnabled:(BOOL)enabled;

#if defined(PINGWARDEN_MIGRATION_HELPER) && PINGWARDEN_MIGRATION_HELPER

/// Observe physical UP plus idle enforcement and cleared recovery state.
/// Unknown, absent or unreadable interfaces are not safe receiver acquisition.
- (BOOL)migrationReceiverCanAcquire;

/// Drop receiver enforcement even when physical restoration fails. Never use
/// this to revoke a legacy hold. Does not stop the shared monitoring thread.
- (BOOL)migrationRelinquishReceiverProtection;
#endif

/// Stop the monitoring thread and cleanup all resources.
/// Should be called before the helper exits.
- (void)invalidate;

/// Exit-path safety net: bring awdl0 back UP with a direct ioctl on the
/// calling thread, but only if this helper (or an earlier instance that
/// died without restoring it) lowered the interface. An interface that
/// macOS or another tool took down is left alone. Call only after
/// `invalidate`.
- (void)restoreInterfaceIfLowered;

/// Get the total number of attempts to turn off AWDL, including failed writes.
/// This counter persists for the lifetime of the helper process
- (NSInteger)getInterventionCount;

/// Reset the intervention counter to zero
- (void)resetInterventionCount;

@end

NS_ASSUME_NONNULL_END
