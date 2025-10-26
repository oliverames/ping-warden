//
//  main.m
//  AWDLControlHelper
//
//  Privileged helper tool for AWDLControl
//  Implements XPC service to load/unload the AWDL monitoring daemon
//  Installed via SMJobBless, runs with root privileges
//

#import <Foundation/Foundation.h>
#import "AWDLHelperProtocal.h"

@interface AWDLHelper : NSObject <NSXPCListenerDelegate, AWDLHelperProtocol>
@property (atomic, strong, readwrite) NSXPCListener *listener;
@end

@implementation AWDLHelper

- (id)init {
    self = [super init];
    if (self) {
        // Set up XPC listener
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.awdlcontrol.helper"];
        self->_listener.delegate = self;
    }
    return self;
}

- (void)run {
    // Start listening for XPC connections
    [self.listener resume];
    [[NSRunLoop currentRunLoop] run];
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // Configure the connection
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AWDLHelperProtocol)];
    newConnection.exportedObject = self;

    // Validate the connection is from our app
    // In production, you could add more strict validation based on code signature

    // Handle invalidation
    newConnection.invalidationHandler = ^{
        NSLog(@"AWDLHelper: Connection invalidated");
    };

    newConnection.interruptionHandler = ^{
        NSLog(@"AWDLHelper: Connection interrupted");
    };

    // Resume the connection
    [newConnection resume];

    NSLog(@"AWDLHelper: Accepted new connection");
    return YES;
}

#pragma mark - AWDLHelperProtocol Implementation

- (void)getVersionWithReply:(void(^)(NSString *version))reply {
    NSLog(@"AWDLHelper: getVersion called");
    reply(@"1.0");
}

- (void)loadDaemonWithReply:(void(^)(NSError *error))reply {
    NSLog(@"AWDLHelper: loadDaemon called");

    NSString *daemonLabel = @"com.awdlcontrol.daemon";
    NSString *plistPath = @"/Library/LaunchDaemons/com.awdlcontrol.daemon.plist";

    // Check if plist exists
    if (![[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
        NSError *error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"Daemon plist not found. Please run install_daemon.sh first."}];
        NSLog(@"AWDLHelper: Error - daemon plist not found at %@", plistPath);
        reply(error);
        return;
    }

    // Use launchctl to load the daemon
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"load", @"-w", plistPath];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *error = nil;
    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus != 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            // If already loaded, that's OK
            if ([output containsString:@"Already loaded"] || [output containsString:@"already loaded"]) {
                NSLog(@"AWDLHelper: Daemon already loaded (not an error)");
                reply(nil);
                return;
            }

            error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                       code:task.terminationStatus
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to load daemon: %@", output]}];
            NSLog(@"AWDLHelper: launchctl load failed with status %d: %@", task.terminationStatus, output);
        } else {
            NSLog(@"AWDLHelper: Successfully loaded daemon");
        }
    }
    @catch (NSException *exception) {
        error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                   code:-1
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception launching launchctl: %@", exception.reason]}];
        NSLog(@"AWDLHelper: Exception launching launchctl: %@", exception);
    }

    reply(error);
}

- (void)unloadDaemonWithReply:(void(^)(NSError *error))reply {
    NSLog(@"AWDLHelper: unloadDaemon called");

    NSString *plistPath = @"/Library/LaunchDaemons/com.awdlcontrol.daemon.plist";

    // Use launchctl to unload the daemon
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"unload", @"-w", plistPath];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    NSError *error = nil;
    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus != 0) {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

            // If not loaded, that's OK
            if ([output containsString:@"Could not find"] || [output containsString:@"not loaded"]) {
                NSLog(@"AWDLHelper: Daemon not loaded (not an error)");
                reply(nil);
                return;
            }

            error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                       code:task.terminationStatus
                                   userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to unload daemon: %@", output]}];
            NSLog(@"AWDLHelper: launchctl unload failed with status %d: %@", task.terminationStatus, output);
        } else {
            NSLog(@"AWDLHelper: Successfully unloaded daemon");
        }
    }
    @catch (NSException *exception) {
        error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                   code:-1
                               userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Exception launching launchctl: %@", exception.reason]}];
        NSLog(@"AWDLHelper: Exception launching launchctl: %@", exception);
    }

    reply(error);
}

- (void)isDaemonLoadedWithReply:(void(^)(BOOL loaded))reply {
    NSLog(@"AWDLHelper: isDaemonLoaded called");

    NSString *daemonLabel = @"com.awdlcontrol.daemon";

    // Use launchctl to check if daemon is loaded
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"list", daemonLabel];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];

        BOOL loaded = (task.terminationStatus == 0);
        NSLog(@"AWDLHelper: Daemon loaded status: %@", loaded ? @"YES" : @"NO");
        reply(loaded);
    }
    @catch (NSException *exception) {
        NSLog(@"AWDLHelper: Exception checking daemon status: %@", exception);
        reply(NO);
    }
}

@end

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSLog(@"AWDLHelper: Starting privileged helper tool");

        AWDLHelper *helper = [[AWDLHelper alloc] init];
        [helper run];
    }

    return EXIT_SUCCESS;
}
