// Copyright (c) 2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.
#pragma once

#if defined(PINGWARDEN_MIGRATION_HELPER) && PINGWARDEN_MIGRATION_HELPER
#import <Foundation/Foundation.h>
#import <sys/types.h>
#import "PingWardenMonitor.h"

NS_ASSUME_NONNULL_BEGIN
/// Replaces only the service implementation in a migration-helper build.
/// The listener and every connection retain the original legacy requirement.
@interface PingWardenService : NSObject <NSXPCListenerDelegate>
@property (nonatomic, strong, readonly) PingWardenMonitor *monitor;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (nullable instancetype)initWithVersion:(NSString *)version
    consoleUIDProvider:(uid_t (^)(void))consoleUIDProvider
    exitGracePeriod:(NSTimeInterval)exitGracePeriod;
- (void)scheduleExitWithReason:(NSString *)reason;
- (void)shutdownWithCompletion:(dispatch_block_t)completion;
@end
NS_ASSUME_NONNULL_END
#endif
