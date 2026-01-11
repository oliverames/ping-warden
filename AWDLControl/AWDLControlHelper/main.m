//
//  main.m
//  AWDLControlHelper
//
//  XPC service entry point for the privileged helper daemon.
//  Registered via SMAppService, runs as LaunchDaemon.
//  Based on james-howard/AWDLControl architecture.
//
//  Copyright (c) 2025 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <os/log.h>

#import "../Common/HelperProtocol.h"
#import "AWDLMonitor.h"

#define LOG OS_LOG_DEFAULT
#define HELPER_VERSION @"2.0.1"

// Team ID for code signing validation
#define TEAM_ID @"PV3W52NDZ3"

// Grace period before exiting when all connections close (allows reconnection)
#define EXIT_GRACE_PERIOD_SECONDS 5.0

static NSInteger activeConnectionCount = 0;
static dispatch_queue_t connectionCountQueue;
static dispatch_source_t exitTimer = nil;

#pragma mark - Code Signing Helpers

/// Check if this binary is properly code signed (not ad-hoc)
static BOOL isProperlyCodeSigned(void) {
    SecCodeRef code = NULL;
    OSStatus status = SecCodeCopySelf(kSecCSDefaultFlags, &code);
    if (status != errSecSuccess || !code) {
        return NO;
    }

    // Check for valid signature (not ad-hoc)
    SecRequirementRef requirement = NULL;
    NSString *reqString = [NSString stringWithFormat:
        @"anchor apple generic and certificate leaf[subject.OU] = \"%@\"", TEAM_ID];
    status = SecRequirementCreateWithString((__bridge CFStringRef)reqString,
                                            kSecCSDefaultFlags, &requirement);
    if (status != errSecSuccess || !requirement) {
        CFRelease(code);
        return NO;
    }

    status = SecCodeCheckValidity(code, kSecCSDefaultFlags, requirement);
    CFRelease(code);
    CFRelease(requirement);

    return status == errSecSuccess;
}

#pragma mark - AWDLService

@interface AWDLService : NSObject <AWDLHelperProtocol, NSXPCListenerDelegate>

@property (strong) AWDLMonitor *monitor;

@end

@implementation AWDLService

- (instancetype)init {
    if (self = [super init]) {
        self.monitor = [AWDLMonitor new];
        if (!self.monitor) {
            os_log_error(LOG, "Failed to initialize AWDLMonitor");
            return nil;
        }
    }
    return self;
}

#pragma mark - AWDLHelperProtocol

- (void)isAWDLEnabledWithReply:(void (^)(BOOL))reply {
    BOOL enabled = self.monitor.awdlEnabled;
    os_log_debug(LOG, "isAWDLEnabled: %d", enabled);
    reply(enabled);
}

- (void)setAWDLEnabled:(BOOL)enable withReply:(void (^)(BOOL))reply {
    os_log(LOG, "setAWDLEnabled: %d", enable);

    // Store previous state to detect if change actually occurred
    BOOL previousState = self.monitor.awdlEnabled;
    self.monitor.awdlEnabled = enable;

    // Verify the state was applied (give a brief moment for the change)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.01 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL currentState = self.monitor.awdlEnabled;
        BOOL success = (currentState == enable);
        if (!success) {
            os_log_error(LOG, "setAWDLEnabled failed: requested %d but state is %d", enable, currentState);
        }
        reply(success);
    });
}

- (void)getAWDLStatusWithReply:(void (^)(NSString *))reply {
    NSString *status = self.monitor.awdlEnabled ? @"AWDL Enabled (allowing UP)" : @"AWDL Disabled (keeping DOWN)";
    os_log_debug(LOG, "getAWDLStatus: %{public}@", status);
    reply(status);
}

- (void)getVersionWithReply:(void (^)(NSString *))reply {
    os_log_debug(LOG, "getVersion: %{public}@", HELPER_VERSION);
    reply(HELPER_VERSION);
}

#pragma mark - Lifecycle

- (void)cancelExitTimer {
    if (exitTimer) {
        dispatch_source_cancel(exitTimer);
        exitTimer = nil;
        os_log_debug(LOG, "Exit timer cancelled - new connection established");
    }
}

- (void)scheduleExit {
    os_log(LOG, "All XPC connections closed, scheduling exit in %.1f seconds", EXIT_GRACE_PERIOD_SECONDS);

    // Cancel any existing timer
    [self cancelExitTimer];

    // Create a new timer that allows reconnection within grace period
    exitTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(exitTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;

        // Double-check no connections were established during grace period
        __block NSInteger currentCount = 0;
        dispatch_sync(connectionCountQueue, ^{
            currentCount = activeConnectionCount;
        });

        if (currentCount > 0) {
            os_log(LOG, "Exit cancelled - %ld active connection(s)", (long)currentCount);
            return;
        }

        os_log(LOG, "Grace period expired, restoring AWDL and exiting");

        // Restore AWDL to enabled state before exiting
        [strongSelf.monitor setAwdlEnabled:YES];
        [strongSelf.monitor invalidate];

        // Give a moment for cleanup, then exit
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            os_log(LOG, "AWDLControlHelper exiting");
            exit(0);
        });
    });

    dispatch_source_set_timer(exitTimer,
                              dispatch_time(DISPATCH_TIME_NOW, (int64_t)(EXIT_GRACE_PERIOD_SECONDS * NSEC_PER_SEC)),
                              DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(exitTimer);
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)conn {
    os_log(LOG, "New XPC connection from PID %d (euid: %d)", conn.processIdentifier, conn.effectiveUserIdentifier);

    // Cancel pending exit if a new connection arrives
    [self cancelExitTimer];

    // Use dispatch_async to avoid potential deadlock from XPC callback context
    dispatch_async(connectionCountQueue, ^{
        activeConnectionCount++;
        os_log_debug(LOG, "Active connections: %ld", (long)activeConnectionCount);
    });

    __weak typeof(self) weakSelf = self;

    conn.interruptionHandler = ^{
        os_log(LOG, "XPC connection interrupted");
    };

    conn.invalidationHandler = ^{
        os_log(LOG, "XPC connection invalidated");

        // Use dispatch_async to avoid deadlock
        dispatch_async(connectionCountQueue, ^{
            activeConnectionCount--;
            os_log_debug(LOG, "Active connections after invalidation: %ld", (long)activeConnectionCount);

            if (activeConnectionCount <= 0) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf scheduleExit];
                });
            }
        });
    };

    conn.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AWDLHelperProtocol)];
    conn.exportedObject = self;
    [conn resume];

    return YES;
}

@end

#pragma mark - Main

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        BOOL isSigned = isProperlyCodeSigned();
        os_log(LOG, "AWDLControlHelper v%{public}@ starting (%{public}s)",
               HELPER_VERSION, isSigned ? "signed" : "unsigned/ad-hoc");

        // Initialize thread-safe queue for connection counting
        connectionCountQueue = dispatch_queue_create("com.awdlcontrol.helper.connectionCount",
                                                     DISPATCH_QUEUE_SERIAL);

        // Initialize the service
        AWDLService *service = [AWDLService new];
        if (!service) {
            os_log_error(LOG, "Failed to create AWDLService, exiting");
            return EXIT_FAILURE;
        }

        // Create XPC listener for our Mach service
        // The service name must match the MachServices key in the plist
        NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.awdlcontrol.xpc.helper"];

        if (!listener) {
            os_log_error(LOG, "Failed to create XPC listener - Mach service may not be registered");
            os_log_error(LOG, "Ensure the helper plist is in Contents/Library/LaunchDaemons/");
            return EXIT_FAILURE;
        }

        // For production builds, enforce code signing requirement
        // This prevents unauthorized processes from connecting to the helper
        if (isSigned) {
            NSString *requirement = [NSString stringWithFormat:
                @"anchor apple generic and identifier \"com.awdlcontrol.app\" "
                @"and certificate leaf[subject.OU] = \"%@\"", TEAM_ID];
            os_log(LOG, "Enforcing code signing requirement for XPC connections");
            // Note: setConnectionCodeSigningRequirement is available in macOS 13+
            // For older versions, manual validation would be needed in shouldAcceptNewConnection
            if (@available(macOS 13.0, *)) {
                listener.connectionCodeSigningRequirement = requirement;
            }
        } else {
            os_log(LOG, "WARNING: Running without code signing - any process can connect");
        }

        listener.delegate = service;
        [listener activate];

        os_log(LOG, "XPC listener activated on com.awdlcontrol.xpc.helper, entering run loop");

        // Enter the main run loop - we'll exit when all connections are closed
        dispatch_main();

        os_log(LOG, "AWDLControlHelper main() exiting");
    }
    return EXIT_SUCCESS;
}
