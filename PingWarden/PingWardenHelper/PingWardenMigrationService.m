// Copyright (c) 2026 Oliver Ames. All rights reserved.
// Licensed under the MIT License.
#if defined(PINGWARDEN_MIGRATION_HELPER) && PINGWARDEN_MIGRATION_HELPER
#import "PingWardenMigrationService.h"
#import "../Common/HelperProtocol.h"
#import <limits.h>
#import <math.h>
#import <unistd.h>

#define LOG PingWardenHelperLog()

// Independent of listener configuration. Receiver admission cannot be enabled
// by changing only main.m's listener requirement.
static NSString * const PWLegacyRequirement = @"anchor apple generic "
    @"and (identifier \"com.amesvt.pingwarden\" or identifier \"com.amesvt.pingwarden.widget\") "
    @"and certificate leaf[subject.OU] = \"PV3W52NDZ3\"";

typedef NS_ENUM(NSInteger, PWClientRole) {
    PWClientRoleLegacy,
    PWClientRoleReceiverApp
};

@class PWClientSession;
@interface PingWardenService () {
@package // Shared only with the private session implementation in this file.
    dispatch_queue_t _controlQueue;
    dispatch_source_t _exitTimer;
    NSMutableDictionary<NSUUID *, PWClientSession *> *_sessions;
    NSString *_version;
    NSString *_legacyRequirement;
    uid_t (^_consoleUIDProvider)(void);
    NSTimeInterval _exitGracePeriod;
    NSUInteger _legacyCount;
    BOOL _legacyGrace;
    BOOL _exiting;
    BOOL _restorationFailed;
    NSUUID *_epoch;
    NSUUID *_generation;
    PWClientSession *_owner;
    NSUUID *_ownerToken;
    NSUUID *_importGeneration;
    BOOL _receiverMayHoldInterface;
    unsigned long long _commandSequence;
}
@property (nonatomic, strong, readwrite) PingWardenMonitor *monitor;
- (void)performSession:(PWClientSession *)session
    operation:(void (^)(PingWardenService *))operation rejected:(dispatch_block_t)rejected;
- (void)loseSession:(PWClientSession *)session interrupted:(BOOL)interrupted;
- (PWReceiverResult)receiverAvailability;
- (PWReceiverResult)ownerResultForSession:(PWClientSession *)session epoch:(NSUUID *)epoch token:(NSUUID *)token;
- (void)cancelExitOnQueue;
- (void)scheduleExitOnQueue;
- (BOOL)revokeOwnerOnQueueInvalidating:(BOOL)invalidate;
- (void)finishShutdownOnQueue:(dispatch_block_t)completion;
@end

@interface PWClientSession : NSObject <PingWardenReceiverProtocol>
@property (nonatomic, weak) PingWardenService *service;
@property (nonatomic, strong) NSXPCConnection *connection;
@property (nonatomic, strong) NSUUID *identifier;
@property (nonatomic) PWClientRole role;
- (void)perform:(void (^)(PingWardenService *))operation rejected:(dispatch_block_t)rejected;
@end

@implementation PingWardenService

- (instancetype)initWithVersion:(NSString *)version
    consoleUIDProvider:(uid_t (^)(void))consoleUIDProvider exitGracePeriod:(NSTimeInterval)exitGracePeriod {
    if (!(self = [super init])) return nil;
    if (version.length == 0 || !consoleUIDProvider
        || !isfinite(exitGracePeriod) || exitGracePeriod <= 0) return nil;
    _version = [version copy];
    _legacyRequirement = PWLegacyRequirement;
    _consoleUIDProvider = [consoleUIDProvider copy];
    _exitGracePeriod = exitGracePeriod;
    _controlQueue = dispatch_queue_create("com.amesvt.pingwarden.helper.control", DISPATCH_QUEUE_SERIAL);
    _sessions = [NSMutableDictionary new];
    _epoch = [NSUUID UUID];
    _generation = [NSUUID UUID];
    _monitor = [PingWardenMonitor new];
    if (!_monitor) return nil;
    // No inference from awdlEnabled. Acquisition performs its own physical read.
    return self;
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection {
    uid_t caller = connection.effectiveUserIdentifier;
    uid_t console = _consoleUIDProvider();
    if (caller != 0 && caller != geteuid() && (console == (uid_t)-1 || caller != console)) return NO;

    // Role classification is intentionally closed. The listener already requires
    // the former team's exact app/widget IDs. Repeat that requirement here so
    // merely widening the listener later cannot expose legacy methods to a receiver.
    // Future receiver admission needs a separately reviewed exact principal mapping
    // and a matching per-connection requirement BEFORE assigning ReceiverApp.
    PWClientRole role = PWClientRoleLegacy;
    @try {
        [connection setCodeSigningRequirement:_legacyRequirement];
    } @catch (NSException *exception) {
        os_log_error(LOG, "Could not enforce the legacy connection requirement");
        return NO;
    }

    PWClientSession *session = [PWClientSession new];
    session.service = self;
    session.connection = connection;
    session.identifier = [NSUUID UUID];
    session.role = role;
    __weak PingWardenService *weakService = self;
    __weak PWClientSession *weakSession = session;
    connection.interruptionHandler = ^{ [weakService loseSession:weakSession interrupted:YES]; };
    connection.invalidationHandler = ^{ [weakService loseSession:weakSession interrupted:NO]; };
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(PingWardenReceiverProtocol)];
    connection.exportedObject = session;
    __block BOOL accepted = NO;
    dispatch_sync(_controlQueue, ^{
        if (self->_exiting) return;
        self->_sessions[session.identifier] = session;
        if (role == PWClientRoleLegacy) {
            self->_legacyCount++;
            self->_legacyGrace = NO;
            [self cancelExitOnQueue];
        }
        // Admission and resume cannot race the serialized shutdown boundary.
        [connection resume];
        accepted = YES;
    });
    if (!accepted) {
        session.connection = nil;
        connection.exportedObject = nil;
        [connection invalidate];
        return NO;
    }
    return YES;
}

- (void)performSession:(PWClientSession *)session
    operation:(void (^)(PingWardenService *))operation rejected:(dispatch_block_t)rejected {
    dispatch_async(_controlQueue, ^{
        if (self->_exiting || self->_sessions[session.identifier] != session) {
            rejected();
            return;
        }
        // Executing an exported message means the connection requirement has
        // been applied. Legacy reads, including getVersion, also preempt.
        if (session.role == PWClientRoleLegacy) [self revokeOwnerOnQueueInvalidating:YES];
        operation(self);
    });
}

- (void)loseSession:(PWClientSession *)session interrupted:(BOOL)interrupted {
    if (!session) return;
    dispatch_async(_controlQueue, ^{
        if (self->_sessions[session.identifier] != session) return;
        // Preserve the existing legacy interruption behavior; invalidation
        // performs its count decrement. Receivers lose ownership immediately.
        if (interrupted && session.role == PWClientRoleLegacy) return;
        if (self->_owner == session) [self revokeOwnerOnQueueInvalidating:NO];
        [self->_sessions removeObjectForKey:session.identifier];
        NSXPCConnection *connection = session.connection;
        session.connection = nil;
        if (session.role == PWClientRoleLegacy && self->_legacyCount > 0) {
            self->_legacyCount--;
            if (self->_legacyCount == 0) self->_legacyGrace = YES;
        }
        if (interrupted) [connection invalidate];
        [self scheduleExitOnQueue];
    });
}

- (PWReceiverResult)receiverAvailability {
    if (_exiting) return PWReceiverResultUnavailable;
    if (_legacyCount > 0) return PWReceiverResultLegacyBusy;
    if (_legacyGrace) return PWReceiverResultLegacyGrace;
    if (_owner) return PWReceiverResultAlreadyOwned;
    if (_restorationFailed || ![self.monitor migrationReceiverCanAcquire]) return PWReceiverResultRestorationUncertain;
    return PWReceiverResultOK;
}

- (PWReceiverResult)ownerResultForSession:(PWClientSession *)session epoch:(NSUUID *)epoch token:(NSUUID *)token {
    if (session.role != PWClientRoleReceiverApp) return PWReceiverResultUnsupportedPrincipal;
    if (_exiting) return PWReceiverResultUnavailable;
    if (![epoch isKindOfClass:[NSUUID class]] || ![token isKindOfClass:[NSUUID class]]
        || ![_epoch isEqual:epoch] || _owner != session || ![_ownerToken isEqual:token]) {
        return PWReceiverResultStaleOwnership;
    }
    return PWReceiverResultOK;
}

- (BOOL)revokeOwnerOnQueueInvalidating:(BOOL)invalidate {
    if (!_owner) return YES;
    PWClientSession *owner = _owner;
    BOOL mayHold = _receiverMayHoldInterface;
    // Retire authority before the physical operation or any client callback.
    _owner = nil;
    _ownerToken = nil;
    _importGeneration = nil;
    _receiverMayHoldInterface = NO;
    _generation = [NSUUID UUID];
    BOOL restored = !mayHold || [self.monitor migrationRelinquishReceiverProtection];
    if (!restored) _restorationFailed = YES; // latched until helper restart
    if (invalidate) {
        [_sessions removeObjectForKey:owner.identifier];
        NSXPCConnection *connection = owner.connection;
        owner.connection = nil;
        [connection invalidate];
    }
    [self scheduleExitOnQueue];
    return restored;
}

- (void)cancelExitOnQueue {
    if (_exitTimer) {
        dispatch_source_cancel(_exitTimer);
        _exitTimer = nil;
    }
}

- (void)scheduleExitOnQueue {
    if (_exiting || _legacyCount > 0 || _owner || _exitTimer) return;
    // Passive receivers never extend the existing legacy disconnect grace.
    _exitTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _controlQueue);
    __weak PingWardenService *weakSelf = self;
    dispatch_source_set_event_handler(_exitTimer, ^{
        PingWardenService *service = weakSelf;
        if (!service || service->_legacyCount > 0 || service->_owner || service->_exiting) return;
        [service finishShutdownOnQueue:^{ exit(0); }];
    });
    dispatch_source_set_timer(_exitTimer, dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(_exitGracePeriod * NSEC_PER_SEC)), DISPATCH_TIME_FOREVER, 0);
    dispatch_resume(_exitTimer);
}

- (void)scheduleExitWithReason:(NSString *)reason {
    dispatch_async(_controlQueue, ^{ [self scheduleExitOnQueue]; });
}

- (void)finishShutdownOnQueue:(dispatch_block_t)completion {
    if (_exiting) return;
    _exiting = YES;
    [self cancelExitOnQueue];
    [self revokeOwnerOnQueueInvalidating:YES];
    for (PWClientSession *session in _sessions.allValues) {
        NSXPCConnection *connection = session.connection;
        session.connection = nil;
        [connection invalidate];
    }
    [_sessions removeAllObjects];
    _legacyCount = 0;
    [self.monitor invalidate];
    [self.monitor restoreInterfaceIfLowered];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
        dispatch_get_main_queue(), completion);
}

- (void)shutdownWithCompletion:(dispatch_block_t)completion {
    dispatch_async(_controlQueue, ^{ [self finishShutdownOnQueue:completion]; });
}
@end

@implementation PWClientSession
- (void)perform:(void (^)(PingWardenService *))operation rejected:(dispatch_block_t)rejected {
    PingWardenService *service = self.service;
    if (!service) { rejected(); return; }
    [service performSession:self operation:operation rejected:rejected];
}

- (void)isAWDLEnabledWithReply:(void (^)(BOOL))reply {
    [self perform:^(PingWardenService *service) {
        reply(self.role == PWClientRoleLegacy ? service.monitor.awdlEnabled : YES);
    } rejected:^{ reply(YES); }];
}
- (void)setAWDLEnabled:(BOOL)enable withReply:(void (^)(BOOL))reply {
    [self perform:^(PingWardenService *service) {
        reply(self.role == PWClientRoleLegacy && [service.monitor setAwdlEnabled:enable]);
    } rejected:^{ reply(NO); }];
}
- (void)getAWDLStatusWithReply:(void (^)(NSString *))reply {
    [self perform:^(PingWardenService *service) {
        if (self.role != PWClientRoleLegacy) { reply(@"Unavailable"); return; }
        reply(service.monitor.awdlEnabled ? @"AWDL Enabled (allowing UP)" : @"AWDL Disabled (keeping DOWN)");
    } rejected:^{ reply(@"Unavailable"); }];
}
- (void)getVersionWithReply:(void (^)(NSString *))reply {
    [self perform:^(PingWardenService *service) { reply(service->_version); } rejected:^{ reply(@""); }];
}
- (void)getAWDLInterventionCountWithReply:(void (^)(NSInteger))reply {
    [self perform:^(PingWardenService *service) {
        reply(self.role == PWClientRoleLegacy ? [service.monitor getInterventionCount] : 0);
    } rejected:^{ reply(0); }];
}
- (void)resetAWDLInterventionCountWithReply:(void (^)(BOOL))reply {
    [self perform:^(PingWardenService *service) {
        if (self.role != PWClientRoleLegacy) { reply(NO); return; }
        [service.monitor resetInterventionCount];
        reply(YES);
    } rejected:^{ reply(NO); }];
}

- (void)receiverStatusWithReply:(void (^)(PWReceiverResult, NSInteger, NSUUID *, NSUUID *))reply {
    [self perform:^(PingWardenService *service) {
        PWReceiverResult result = self.role == PWClientRoleReceiverApp
            ? [service receiverAvailability] : PWReceiverResultUnsupportedPrincipal;
        reply(result, 1, service->_epoch, service->_generation);
    } rejected:^{ reply(PWReceiverResultUnavailable, 0, nil, nil); }];
}

- (void)acquireReceiverOwnershipForEpoch:(NSUUID *)epoch importGeneration:(NSUUID *)importGeneration
    reply:(void (^)(PWReceiverResult, NSUUID *, NSUUID *))reply {
    [self perform:^(PingWardenService *service) {
        PWReceiverResult result = PWReceiverResultOK;
        if (self.role != PWClientRoleReceiverApp) result = PWReceiverResultUnsupportedPrincipal;
        else if (![epoch isKindOfClass:[NSUUID class]] || ![importGeneration isKindOfClass:[NSUUID class]]
            || ![service->_epoch isEqual:epoch]) result = PWReceiverResultStaleOwnership;
        else if (service->_owner == self && [service->_importGeneration isEqual:importGeneration]) {
            reply(PWReceiverResultOK, service->_ownerToken, service->_generation);
            return;
        } else result = [service receiverAvailability];
        if (result != PWReceiverResultOK) { reply(result, nil, service->_generation); return; }
        service->_owner = self;
        service->_ownerToken = [NSUUID UUID];
        service->_importGeneration = [importGeneration copy];
        service->_receiverMayHoldInterface = NO;
        service->_commandSequence = 0;
        service->_generation = [NSUUID UUID];
        [service cancelExitOnQueue];
        reply(PWReceiverResultOK, service->_ownerToken, service->_generation);
    } rejected:^{ reply(PWReceiverResultUnavailable, nil, nil); }];
}

- (void)setReceiverAWDLEnabled:(BOOL)enabled epoch:(NSUUID *)epoch token:(NSUUID *)token
    reply:(void (^)(PWReceiverResult, unsigned long long))reply {
    [self perform:^(PingWardenService *service) {
        PWReceiverResult result = [service ownerResultForSession:self epoch:epoch token:token];
        if (result != PWReceiverResultOK) { reply(result, service->_commandSequence); return; }
        if (service->_commandSequence == ULLONG_MAX) { reply(PWReceiverResultUnavailable, ULLONG_MAX); return; }
        service->_commandSequence++;
        // A failed On confirmation may still follow an ioctl that lowered AWDL.
        if (!enabled) service->_receiverMayHoldInterface = YES;
        BOOL success = [service.monitor setAwdlEnabled:enabled];
        if (enabled && success) service->_receiverMayHoldInterface = NO;
        reply(success ? PWReceiverResultOK : PWReceiverResultOperationFailed, service->_commandSequence);
    } rejected:^{ reply(PWReceiverResultUnavailable, 0); }];
}

- (void)releaseReceiverOwnershipForEpoch:(NSUUID *)epoch token:(NSUUID *)token reply:(void (^)(PWReceiverResult))reply {
    [self perform:^(PingWardenService *service) {
        PWReceiverResult result = [service ownerResultForSession:self epoch:epoch token:token];
        if (result != PWReceiverResultOK) { reply(result); return; }
        BOOL restored = [service revokeOwnerOnQueueInvalidating:NO];
        reply(restored ? PWReceiverResultOK : PWReceiverResultRestorationUncertain);
    } rejected:^{ reply(PWReceiverResultUnavailable); }];
}
@end
#endif
