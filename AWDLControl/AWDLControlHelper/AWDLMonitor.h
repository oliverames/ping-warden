//
//  AWDLMonitor.h
//  AWDLControlHelper
//
//  Monitors AWDL interface state using AF_ROUTE socket.
//  Based on james-howard/AWDLControl and jamestut/awdlkiller.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Monitors and controls the AWDL (awdl0) network interface.
/// Uses AF_ROUTE socket for kernel-level monitoring with <1ms response time.
/// When awdlEnabled is NO, any attempt by the system to bring awdl0 UP
/// is immediately countered by bringing it back DOWN.
@interface AWDLMonitor : NSObject

/// When YES, AWDL is allowed to be up (normal operation).
/// When NO, AWDL is kept down (blocking mode).
/// Setting this property immediately applies the desired state.
@property (nonatomic) BOOL awdlEnabled;

/// Stop the monitoring thread and cleanup all resources.
/// Should be called before the helper exits.
- (void)invalidate;

/// Get the total number of AWDL interventions (how many times we blocked AWDL from coming up)
/// This counter persists for the lifetime of the helper process
- (NSInteger)getInterventionCount;

/// Reset the intervention counter to zero
- (void)resetInterventionCount;

@end

NS_ASSUME_NONNULL_END
