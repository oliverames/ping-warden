//
//  main.m
//  AWDLHelper
//
//  Privileged helper tool that runs as root to manage the AWDL monitoring daemon.
//  Installed via SMJobBless, communicates with app via XPC.
//

#import <Foundation/Foundation.h>
#import "AWDLHelperProtocol.h"

@interface AWDLHelper : NSObject <NSXPCListenerDelegate, AWDLHelperProtocol>
@property (atomic, strong, readwrite) NSXPCListener *listener;
@end

@implementation AWDLHelper

- (id)init {
    self = [super init];
    if (self != nil) {
        // Set up XPC listener for incoming connections from the app
        self->_listener = [[NSXPCListener alloc] initWithMachServiceName:@"com.awdlcontrol.helper"];
        self->_listener.delegate = self;
    }
    return self;
}

- (void)run {
    // Start accepting XPC connections
    [self.listener resume];
    [[NSRunLoop currentRunLoop] run];
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    // Configure the connection
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(AWDLHelperProtocol)];
    newConnection.exportedObject = self;

    // Resume the connection
    [newConnection resume];

    return YES;
}

#pragma mark - AWDLHelperProtocol

- (void)getVersionWithReply:(void(^)(NSString *version))reply {
    reply([NSString stringWithFormat:@"%d", kAWDLHelperProtocolVersion]);
}

- (void)loadDaemonWithReply:(void(^)(NSError *error))reply {
    NSLog(@"AWDLHelper: Loading daemon...");

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"load", @"/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus == 0) {
            NSLog(@"AWDLHelper: Daemon loaded successfully");
            reply(nil);
        } else {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"AWDLHelper: Failed to load daemon: %@", output);

            NSError *error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                               code:task.terminationStatus
                                           userInfo:@{NSLocalizedDescriptionKey: output ?: @"Failed to load daemon"}];
            reply(error);
        }
    } @catch (NSException *exception) {
        NSLog(@"AWDLHelper: Exception loading daemon: %@", exception);
        NSError *error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        reply(error);
    }
}

- (void)unloadDaemonWithReply:(void(^)(NSError *error))reply {
    NSLog(@"AWDLHelper: Unloading daemon...");

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"unload", @"/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];

        if (task.terminationStatus == 0) {
            NSLog(@"AWDLHelper: Daemon unloaded successfully");
            reply(nil);
        } else {
            NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
            NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSLog(@"AWDLHelper: Failed to unload daemon: %@", output);

            NSError *error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                               code:task.terminationStatus
                                           userInfo:@{NSLocalizedDescriptionKey: output ?: @"Failed to unload daemon"}];
            reply(error);
        }
    } @catch (NSException *exception) {
        NSLog(@"AWDLHelper: Exception unloading daemon: %@", exception);
        NSError *error = [NSError errorWithDomain:@"com.awdlcontrol.helper"
                                           code:-1
                                       userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Unknown error"}];
        reply(error);
    }
}

- (void)isDaemonLoadedWithReply:(void(^)(BOOL loaded))reply {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/bin/launchctl";
    task.arguments = @[@"list", @"com.awdlcontrol.daemon"];

    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;

    @try {
        [task launch];
        [task waitUntilExit];

        BOOL loaded = (task.terminationStatus == 0);
        reply(loaded);
    } @catch (NSException *exception) {
        reply(NO);
    }
}

@end

#pragma mark - Main Entry Point

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSLog(@"AWDLHelper: Starting privileged helper tool");

        AWDLHelper *helper = [[AWDLHelper alloc] init];
        [helper run];
    }

    return 0;
}
