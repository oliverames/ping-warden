//
//  PingWardenMonitor.m
//  PingWardenHelper
//
//  Core AWDL monitoring using AF_ROUTE socket.
//  Based on james-howard/AWDLControl and jamestut/awdlkiller.
//
//  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
//  Licensed under the MIT License.
//

#import "PingWardenMonitor.h"

#import <sys/types.h>
#import <sys/ioctl.h>
#import <sys/socket.h>
#import <net/if.h>
#import <net/if_dl.h>
#import <net/route.h>
#import <unistd.h>
#import <poll.h>
#import <errno.h>
#import <err.h>
#import <fcntl.h>
#import <string.h>
#import <stdatomic.h>

#define LOG PingWardenHelperLog()

os_log_t PingWardenHelperLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("com.amesvt.pingwarden", "helper");
    });
    return log;
}

static const char *TARGETIFNAM = "awdl0";

// Static assertion to ensure TARGETIFNAM fits in IFNAMSIZ
// IFNAMSIZ is typically 16 on macOS/BSD
_Static_assert(sizeof("awdl0") <= IFNAMSIZ, "TARGETIFNAM must fit in IFNAMSIZ");

// Routing messages can contain rt_msghdr + if_msghdr + multiple sockaddr structures
// Use a generous buffer size to handle all message types safely
#define RTMSG_BUFFER_SIZE 512

// The default AF_ROUTE receive buffer is 8 KB, about 64 messages. A wake
// from sleep or a network change can exceed that, and the kernel drops the
// newest messages silently. A larger buffer makes that rarer; reconciling
// against the interface's actual flags makes it harmless.
#define RTSOCK_RECEIVE_BUFFER_BYTES (256 * 1024)

// While blocking, re-check awdl0 at least this often even without route
// messages, and retry sooner after a failed write.
#define DEFAULT_RECONCILE_INTERVAL_MS 5000
#define DEFAULT_RETRY_INTERVAL_MS 250

// Present while this helper holds awdl0 down. /var/run is cleared at boot,
// so a marker found at startup means an earlier helper died mid-session.
#define DEFAULT_LOWERED_MARKER_PATH @"/var/run/com.amesvt.pingwarden.helper.awdl-lowered"

// Log the first interventions at the default level, then only every
// hundredth, so a long fight with AirDrop does not flood the persisted log.
#define INTERVENTION_LOG_BURST 10
#define INTERVENTION_LOG_EVERY 100

// Invalid file descriptor sentinel
#define INVALID_FD (-1)

@interface PingWardenMonitor () {
    // Pipe file descriptors for internal state change communication
    int _msgfds[2];

    // Thread-safe flag for tracking background thread state
    // Use atomic_bool to prevent data races between main thread and pollIoctl thread
    atomic_bool _threadRunning;

    // Desired AWDL state — accessed from XPC handler threads and the setter,
    // so use atomic_bool to prevent data races.
    atomic_bool _awdlEnabledAtomic;

    // Set when the last enforcement write failed, so the poller retries on
    // its short interval instead of waiting for the next route message.
    atomic_bool _enforcementPending;

    dispatch_semaphore_t _ioctlThreadExitSemaphore;
    // Serialize interface operations with route enforcement and shutdown.
    NSLock *_interfaceLock;
    BOOL _invalidating;

    // YES once this process has written awdl0 down, until it confirms awdl0
    // up again. Guarded by _interfaceLock.
    BOOL _loweredByHelper;
    BOOL _loggedMissingInterface;
    // Stop watching a route socket that keeps reporting hard errors, so a
    // broken descriptor cannot spin the poller; timeouts still reconcile.
    atomic_bool _routeSocketBroken;

    // Counter for attempts to turn off AWDL, including failed writes.
    atomic_long _interventionCount;
}

/// Background thread watching AWDL state
@property NSThread *ioctlThread;

/// Socket to perform ioctl to set interface flags
@property int iocfd;

/// Socket to monitor network interface changes (AF_ROUTE)
@property int rtfd;

/// Where the lowered-interface marker lives. Tests point it at a temporary path.
@property (copy) NSString *loweredMarkerPath;

/// Poll timeout while blocking, and the retry timeout after a failed write.
@property int reconcileIntervalMs;
@property int retryIntervalMs;

@end

@implementation PingWardenMonitor

- (instancetype)init {
    return [self initWithLoweredMarkerPath:DEFAULT_LOWERED_MARKER_PATH];
}

- (instancetype)initWithLoweredMarkerPath:(NSString *)markerPath {
    if (self = [super init]) {
        _interfaceLock = [NSLock new];
        _loweredMarkerPath = [markerPath copy];
        _reconcileIntervalMs = DEFAULT_RECONCILE_INTERVAL_MS;
        _retryIntervalMs = DEFAULT_RETRY_INTERVAL_MS;
        // Initialize file descriptors to invalid state for proper cleanup
        _rtfd = INVALID_FD;
        _iocfd = INVALID_FD;
        _msgfds[0] = INVALID_FD;
        _msgfds[1] = INVALID_FD;
        atomic_store(&_threadRunning, false);
        atomic_store(&_enforcementPending, false);
        atomic_store(&_routeSocketBroken, false);

        // Initialize intervention counter
        atomic_store(&_interventionCount, 0);

        // Start off allowing AWDL to be active
        atomic_store(&_awdlEnabledAtomic, true);

        // Socket to monitor network interface changes
        _rtfd = socket(AF_ROUTE, SOCK_RAW, 0);
        if (_rtfd < 0) {
            os_log_error(LOG, "Error creating AF_ROUTE socket: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }
        if (fcntl(_rtfd, F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on AF_ROUTE socket: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }
        int receiveBuffer = RTSOCK_RECEIVE_BUFFER_BYTES;
        if (setsockopt(_rtfd, SOL_SOCKET, SO_RCVBUF, &receiveBuffer, sizeof(receiveBuffer)) < 0) {
            // Not fatal: reconciliation covers dropped messages.
            os_log_info(LOG, "Could not enlarge the AF_ROUTE receive buffer: %d (%s)", errno, strerror(errno));
        }

        // Socket to perform ioctl to set interface flags
        _iocfd = socket(AF_INET, SOCK_DGRAM, 0);
        if (_iocfd < 0) {
            os_log_error(LOG, "Error creating AF_INET socket: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }

        // Pipe for communication from main thread to ioctl thread
        if (0 != pipe(_msgfds)) {
            os_log_error(LOG, "Error creating pipe: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }
        // Set both pipe ends to non-blocking so XPC handler threads cannot
        // hang behind a full control pipe during rapid toggle/reconnect churn.
        if (fcntl(_msgfds[0], F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on pipe read fd: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }
        if (fcntl(_msgfds[1], F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on pipe write fd: %d (%s)", errno, strerror(errno));
            [self cleanupFileDescriptors];
            return nil;
        }

        [self restoreAfterUncleanExitIfNeeded];

        // Start background thread
        _ioctlThreadExitSemaphore = dispatch_semaphore_create(0);
        _ioctlThread = [[NSThread alloc] initWithTarget:self selector:@selector(pollIoctl) object:nil];
        _ioctlThread.name = @"PingWardenMonitor.pollIoctl";
        // Reaction time from awdl0 UP to DOWN is the product's core metric.
        _ioctlThread.qualityOfService = NSQualityOfServiceUserInteractive;
        atomic_store(&_threadRunning, true);
        [_ioctlThread start];

        os_log(LOG, "PingWardenMonitor initialized successfully");
    }
    return self;
}

/// Clean up file descriptors on error or dealloc
- (void)cleanupFileDescriptors {
    [_interfaceLock lock];
    if (_iocfd != INVALID_FD) {
        close(_iocfd);
        _iocfd = INVALID_FD;
    }
    if (_rtfd != INVALID_FD) {
        close(_rtfd);
        _rtfd = INVALID_FD;
    }
    if (_msgfds[0] != INVALID_FD) {
        close(_msgfds[0]);
        _msgfds[0] = INVALID_FD;
    }
    if (_msgfds[1] != INVALID_FD) {
        close(_msgfds[1]);
        _msgfds[1] = INVALID_FD;
    }
    [_interfaceLock unlock];
}

#pragma mark - Lowered-interface marker

- (BOOL)loweredMarkerExists {
    NSString *path = self.loweredMarkerPath;
    return path.length > 0 && access(path.fileSystemRepresentation, F_OK) == 0;
}

/// Caller holds _interfaceLock.
- (void)recordLoweredLocked {
    // Repeated interventions within one lowered stretch need no more writes.
    if (_loweredByHelper) return;
    _loweredByHelper = YES;
    NSString *path = self.loweredMarkerPath;
    if (path.length == 0) return;
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0644);
    if (fd < 0) {
        os_log_error(LOG, "Could not write the lowered-interface marker: %d (%s)", errno, strerror(errno));
        return;
    }
    close(fd);
}

/// Caller holds _interfaceLock.
- (void)clearLoweredLocked {
    _loweredByHelper = NO;
    NSString *path = self.loweredMarkerPath;
    if (path.length == 0) return;
    if (unlink(path.fileSystemRepresentation) < 0 && errno != ENOENT) {
        os_log_error(LOG, "Could not remove the lowered-interface marker: %d (%s)", errno, strerror(errno));
    }
}

/// An earlier helper that crashed or was killed while blocking leaves awdl0
/// down with no owner. Restore it before serving; a client that still wants
/// protection reasserts it after connecting.
- (void)restoreAfterUncleanExitIfNeeded {
    if (![self loweredMarkerExists]) return;
    os_log(LOG, "An earlier helper left awdl0 down; restoring it before serving");
    [_interfaceLock lock];
    if (![self ifconfig:YES]) {
        os_log_error(LOG, "Could not restore awdl0 after an unclean exit; will retry on the next launch");
    }
    [_interfaceLock unlock];
}

#pragma mark - Interface control

/// Apply and confirm interface flags while holding _interfaceLock.
- (BOOL)ifconfig:(BOOL)up {
    struct ifreq ifr = {0};
    strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);

    if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
        os_log_error(LOG, "Error getting current interface flags: %d (%s)", errno, strerror(errno));
        return NO;
    }

    if ((ifr.ifr_flags & IFF_UP) && !up) {
        // Interface is UP but we want it DOWN
        ifr.ifr_flags &= ~IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interface down: %d (%s)", errno, strerror(errno));
            return NO;
        } else {
            os_log_debug(LOG, "Brought awdl0 DOWN");
            [self recordLoweredLocked];
        }
    } else if (!(ifr.ifr_flags & IFF_UP) && up) {
        // Interface is DOWN but we want it UP
        ifr.ifr_flags |= IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interface up: %d (%s)", errno, strerror(errno));
            return NO;
        } else {
            os_log_debug(LOG, "Brought awdl0 UP");
        }
    }
    // Read back even when no write was needed. Never turn command acceptance
    // into a claim that the interface reached the requested state.
    if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
        os_log_error(LOG, "Error confirming interface flags: %d (%s)", errno, strerror(errno));
        return NO;
    }
    BOOL confirmed = !!(ifr.ifr_flags & IFF_UP) == up;
    if (confirmed && up) {
        [self clearLoweredLocked];
    }
    return confirmed;
}

/// Caller holds _interfaceLock. Lowers awdl0 when blocking is armed and the
/// flags show it up. Returns NO only when a needed write did not take.
- (BOOL)enforceBlockingForFlagsLocked:(int)flags {
    if (_invalidating || !atomic_load(&_threadRunning) ||
        atomic_load(&_awdlEnabledAtomic) || !(flags & IFF_UP)) {
        return YES;
    }
    long count = atomic_fetch_add(&_interventionCount, 1) + 1;
    if (count <= INTERVENTION_LOG_BURST || count % INTERVENTION_LOG_EVERY == 0) {
        os_log(LOG, "AWDL intervention attempt #%ld", count);
    } else {
        os_log_debug(LOG, "AWDL intervention attempt #%ld", count);
    }
    return [self ifconfig:NO];
}

- (void)handleInterfaceFlags:(int)flags {
    [_interfaceLock lock];
    // Reload intent under the same lock as commands. A queued route event
    // must not undo a newer successful stop or an exit-path restoration.
    atomic_store(&_enforcementPending, ![self enforceBlockingForFlagsLocked:flags]);
    [_interfaceLock unlock];
}

/// Enforce blocking against the interface's actual flags. Route messages
/// only say "look now": the kernel drops them silently when the socket
/// buffer fills, so the flags themselves are the source of truth.
- (void)reconcileInterface {
    [_interfaceLock lock];
    BOOL pending = NO;
    if (!_invalidating && atomic_load(&_threadRunning) && !atomic_load(&_awdlEnabledAtomic)) {
        struct ifreq ifr = {0};
        strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);
        if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
            if (errno == ENXIO) {
                // No awdl0 (a virtual machine, for example): nothing to block.
                if (!_loggedMissingInterface) {
                    os_log(LOG, "awdl0 does not exist on this Mac; nothing to block");
                    _loggedMissingInterface = YES;
                }
            } else {
                os_log_error(LOG, "Error reading awdl0 flags during reconcile: %d (%s)", errno, strerror(errno));
                pending = YES;
            }
        } else {
            _loggedMissingInterface = NO;
            pending = ![self enforceBlockingForFlagsLocked:ifr.ifr_flags];
        }
    }
    atomic_store(&_enforcementPending, pending);
    [_interfaceLock unlock];
}

#pragma mark - Poll thread

/// Discard queued route messages. Their content no longer matters because
/// reconciliation reads the interface directly. Returns NO on a hard error.
- (BOOL)drainRouteSocket {
    uint8_t rtmsgbuff[RTMSG_BUFFER_SIZE];
    for (;;) {
        ssize_t len = read(_rtfd, rtmsgbuff, sizeof(rtmsgbuff));
        if (len > 0) continue;
        if (len < 0 && errno == EINTR) continue;
        if (len < 0 && errno == EAGAIN) return YES;
        if (len == 0) {
            os_log_error(LOG, "AF_ROUTE socket closed");
        } else {
            os_log_error(LOG, "Error reading AF_ROUTE socket: %d (%s)", errno, strerror(errno));
        }
        return NO;
    }
}

/// Read control bytes. Returns YES when a quit message arrived.
- (BOOL)drainControlPipe {
    char msg = 0;
    for (;;) {
        ssize_t len = read(_msgfds[0], &msg, 1);
        if (len < 0) {
            if (errno == EINTR) continue;
            if (errno != EAGAIN) {
                os_log_error(LOG, "Error reading message pipe: %d (%s)", errno, strerror(errno));
            }
            return NO;
        }
        if (len == 0) return NO;  // Pipe closed
        switch (msg) {
            case 'Q':
                os_log(LOG, "Received quit message");
                return YES;
            case 'W':
                // Wake only: the loop re-reads the blocking intent.
                break;
            default:
                os_log_debug(LOG, "Unknown message: %c", msg);
                break;
        }
    }
}

/// Main method for the background ioctlThread.
/// While blocking, it watches AF_ROUTE and a periodic timeout, and each
/// wakeup reconciles awdl0 against the blocking intent. While allowing, it
/// sleeps on the control pipe alone, so a resident helper costs nothing.
- (void)pollIoctl {
    os_log(LOG, "pollIoctl thread started");

    BOOL quit = NO;
    int consecutivePollErrors = 0;

    while (!quit) {
        @autoreleasepool {
            BOOL blocking = !atomic_load(&_awdlEnabledAtomic);
            BOOL watchRoutes = blocking && !atomic_load(&_routeSocketBroken);
            int timeout = -1;
            if (blocking) {
                timeout = atomic_load(&_enforcementPending) ? self.retryIntervalMs : self.reconcileIntervalMs;
            }

            struct pollfd fds[] = {
                { .fd = _msgfds[0], .events = POLLIN, .revents = 0 },
                { .fd = _rtfd, .events = POLLIN, .revents = 0 },
            };

            int ready = poll(fds, watchRoutes ? 2 : 1, timeout);
            if (ready < 0) {
                if (errno == EINTR) {
                    continue;
                }
                // Transient failures (ENOMEM, EAGAIN) must not end
                // enforcement; back off and try again.
                consecutivePollErrors++;
                if (consecutivePollErrors == 1 || consecutivePollErrors % 100 == 0) {
                    os_log_fault(LOG, "Poll error %d (%s), attempt %d; retrying",
                                 errno, strerror(errno), consecutivePollErrors);
                }
                usleep(100 * 1000);
                continue;
            }
            consecutivePollErrors = 0;

            if (ready == 0) {
                // Periodic check while blocking, or a retry after a failed write.
                [self reconcileInterface];
                continue;
            }

            if (watchRoutes && fds[1].revents) {
                if (![self drainRouteSocket] || (fds[1].revents & (POLLERR | POLLHUP | POLLNVAL))) {
                    os_log_error(LOG, "AF_ROUTE socket failed; falling back to periodic checks");
                    atomic_store(&_routeSocketBroken, true);
                }
                [self reconcileInterface];
            }

            if (fds[0].revents) {
                quit = [self drainControlPipe];
            }
        }
    }

    atomic_store(&_threadRunning, false);
    dispatch_semaphore_signal(_ioctlThreadExitSemaphore);
    os_log(LOG, "pollIoctl thread exiting");
}

/// Write a single byte to the message pipe with retry logic
- (BOOL)writeMessageToPipe:(const char *)msg {
    if (_msgfds[1] == INVALID_FD) {
        os_log_error(LOG, "Cannot write to pipe: fd is invalid");
        return NO;
    }

    // Retry up to 3 times on EINTR
    for (int retry = 0; retry < 3; retry++) {
        ssize_t written = write(_msgfds[1], msg, 1);
        if (written == 1) {
            return YES;
        }
        if (written < 0) {
            if (errno == EINTR) {
                os_log_debug(LOG, "Write interrupted, retrying (attempt %d)", retry + 1);
                continue;
            }
            os_log_error(LOG, "Error writing to message pipe: %d (%s)", errno, strerror(errno));
            return NO;
        }
        // written == 0 means nothing was written
        os_log_info(LOG, "Partial write to message pipe: wrote %zd bytes", written);
    }
    os_log_error(LOG, "Failed to write message after 3 retries");
    return NO;
}

/// Nudge the poller to re-read the blocking intent. A full pipe already
/// holds a pending wake, so EAGAIN is not an error here.
- (void)wakePoller {
    if (_msgfds[1] == INVALID_FD) return;
    const char msg = 'W';
    ssize_t written;
    do {
        written = write(_msgfds[1], &msg, 1);
    } while (written < 0 && errno == EINTR);
    if (written < 0 && errno != EAGAIN) {
        os_log_error(LOG, "Could not wake the poll thread: %d (%s)", errno, strerror(errno));
    }
}

#pragma mark - Public API

- (BOOL)awdlEnabled {
    [_interfaceLock lock];
    BOOL enabled = YES;
    if (!_invalidating && atomic_load(&_threadRunning) &&
        !atomic_load(&_awdlEnabledAtomic)) {
        struct ifreq ifr = {0};
        strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);
        if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
            // An unreadable interface cannot be presented as protected.
            enabled = YES;
        } else if (ifr.ifr_flags & IFF_UP) {
            // macOS can raise awdl0 an instant before the poller lowers it.
            // Enforce first, so a read taken in that window reports what
            // the helper holds rather than the transient. A write that does
            // not take is still reported as unprotected.
            enabled = ![self enforceBlockingForFlagsLocked:ifr.ifr_flags];
        } else {
            enabled = NO;
        }
    }
    [_interfaceLock unlock];
    return enabled;
}

- (BOOL)setAwdlEnabled:(BOOL)enabled {
    [_interfaceLock lock];
    // Blocking needs the poll thread to hold awdl0 down. Allowing only needs
    // the interface, so a dead poller can never trap AWDL down.
    if (_invalidating || (!enabled && !atomic_load(&_threadRunning))) {
        os_log_error(LOG, "Cannot set AWDL state to %d: monitor thread is not running", enabled);
        [_interfaceLock unlock];
        return NO;
    }
    BOOL success = [self ifconfig:enabled];
    if (success) {
        atomic_store(&_awdlEnabledAtomic, enabled);
        atomic_store(&_enforcementPending, false);
    }
    [_interfaceLock unlock];
    if (success) {
        [self wakePoller];
    }
    return success;
}

- (void)restoreInterfaceIfLowered {
    // Last-resort restore used on exit paths. Performs the ioctl directly on
    // the calling thread with a transient socket, so it works even when the
    // poll thread is dead or the control pipe is gone. Must only run after
    // `invalidate` (the poll thread no longer touches interface flags).
    [_interfaceLock lock];
    atomic_store(&_awdlEnabledAtomic, true);
    BOOL lowered = _loweredByHelper || [self loweredMarkerExists];
    if (!lowered) {
        os_log_debug(LOG, "awdl0 was not lowered by the helper; leaving it as macOS set it");
        [_interfaceLock unlock];
        return;
    }

    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        os_log_error(LOG, "restoreInterfaceIfLowered: socket failed: %d (%s)", errno, strerror(errno));
        [_interfaceLock unlock];
        return;
    }

    struct ifreq ifr = {0};
    strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);
    if (ioctl(fd, SIOCGIFFLAGS, &ifr) < 0) {
        os_log_error(LOG, "restoreInterfaceIfLowered: SIOCGIFFLAGS failed: %d (%s)", errno, strerror(errno));
        close(fd);
        [_interfaceLock unlock];
        return;
    }

    BOOL up = !!(ifr.ifr_flags & IFF_UP);
    if (!up) {
        ifr.ifr_flags |= IFF_UP;
        if (ioctl(fd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "restoreInterfaceIfLowered: SIOCSIFFLAGS failed: %d (%s)", errno, strerror(errno));
        } else {
            up = YES;
            os_log(LOG, "Restored awdl0 UP via direct ioctl before exit");
        }
    }
    if (up) {
        // Keep the marker when the restore failed so the next instance retries.
        [self clearLoweredLocked];
    }
    close(fd);
    [_interfaceLock unlock];
}

- (void)invalidate {
    os_log(LOG, "PingWardenMonitor invalidating...");
    [_interfaceLock lock];
    _invalidating = YES;
    atomic_store(&_awdlEnabledAtomic, true);
    [_interfaceLock unlock];

    // Only send quit if thread is running (atomic read)
    if (atomic_load(&_threadRunning) && _msgfds[1] != INVALID_FD) {
        // Send quit message to background thread with retry
        if (![self writeMessageToPipe:"Q"]) {
            os_log_error(LOG, "Failed to send quit message to pipe - thread may not exit cleanly");
        }

        // Wait for background thread to exit (with timeout)
        // Use a shorter initial timeout, then check if thread is still running
        dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC));
        long result = dispatch_semaphore_wait(_ioctlThreadExitSemaphore, timeout);
        if (result != 0) {
            os_log_error(LOG, "Timeout waiting for pollIoctl thread to exit");
            // Mark thread as not running to prevent further issues (atomic write)
            atomic_store(&_threadRunning, false);
            // Deliberately leak the fds: the poller may still be blocked in
            // poll()/read() on them, and closing here would let the process
            // recycle the descriptor numbers underneath a live reader. Both
            // callers exit the process moments later, so the leak is bounded.
            os_log(LOG, "PingWardenMonitor invalidated (fds leaked pending process exit)");
            return;
        }
    }

    // Clean up file descriptors after thread exits
    [self cleanupFileDescriptors];

    os_log(LOG, "PingWardenMonitor invalidated");
}

- (void)dealloc {
    // Ensure thread is stopped and resources cleaned up (atomic read)
    if (atomic_load(&_threadRunning)) {
        [self invalidate];
    } else {
        [self cleanupFileDescriptors];
    }
}

#pragma mark - Intervention Counter

- (NSInteger)getInterventionCount {
    return (NSInteger)atomic_load(&_interventionCount);
}

- (void)resetInterventionCount {
    atomic_store(&_interventionCount, 0);
    os_log(LOG, "Intervention counter reset to 0");
}

@end
