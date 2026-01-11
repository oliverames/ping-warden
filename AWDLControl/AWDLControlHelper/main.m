//
//  main.m
//  AWDLControlHelper
//
//  XPC service entry point for the privileged helper daemon.
//  Registered via SMAppService, runs as LaunchDaemon.
//  Based on james-howard/AWDLControl architecture.
//

#import <Foundation/Foundation.h>
#import <os/log.h>

#import "../Common/HelperProtocol.h"
#import "AWDLMonitor.h"

#define LOG OS_LOG_DEFAULT
#define HELPER_VERSION @"2.0.0"

static NSInteger activeConnectionCount = 0;

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
    self.monitor.awdlEnabled = enable;
    reply(YES);
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

- (void)scheduleExit {
    os_log(LOG, "All XPC connections closed, restoring AWDL and exiting");

    // Restore AWDL to enabled state before exiting
    [self.monitor setAwdlEnabled:YES];
    [self.monitor invalidate];

    // Give a moment for cleanup, then exit
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        os_log(LOG, "AWDLControlHelper exiting");
        exit(0);
    });
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)conn {
    os_log(LOG, "New XPC connection from PID %d (euid: %d)", conn.processIdentifier, conn.effectiveUserIdentifier);

    activeConnectionCount++;
    os_log_debug(LOG, "Active connections: %ld", (long)activeConnectionCount);

    __weak typeof(self) weakSelf = self;

    conn.interruptionHandler = ^{
        os_log(LOG, "XPC connection interrupted");
    };

    conn.invalidationHandler = ^{
        os_log(LOG, "XPC connection invalidated");
        activeConnectionCount--;
        os_log_debug(LOG, "Active connections after invalidation: %ld", (long)activeConnectionCount);

        if (activeConnectionCount <= 0) {
            [weakSelf scheduleExit];
        }
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
        os_log(LOG, "AWDLControlHelper v%{public}@ starting (unsigned build)", HELPER_VERSION);

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

        // IMPORTANT: For unsigned builds, we do NOT set connectionCodeSigningRequirement
        // This allows any local process to connect. For signed distribution builds,
        // you would add:
        // [listener setConnectionCodeSigningRequirement:@"anchor apple generic and identifier \"com.awdlcontrol.app\""];

        listener.delegate = service;
        [listener activate];

        os_log(LOG, "XPC listener activated on com.awdlcontrol.xpc.helper, entering run loop");

        // Enter the main run loop - we'll exit when all connections are closed
        dispatch_main();

        os_log(LOG, "AWDLControlHelper main() exiting");
    }
    return EXIT_SUCCESS;
}
