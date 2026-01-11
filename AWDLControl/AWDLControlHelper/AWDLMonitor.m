//
//  AWDLMonitor.m
//  AWDLControlHelper
//
//  Core AWDL monitoring using AF_ROUTE socket.
//  Based on james-howard/AWDLControl and jamestut/awdlkiller.
//

#import "AWDLMonitor.h"

#import <os/log.h>
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

#define LOG OS_LOG_DEFAULT

static const char *TARGETIFNAM = "awdl0";

// Routing messages can contain rt_msghdr + if_msghdr + multiple sockaddr structures
// Use a generous buffer size to handle all message types safely
#define RTMSG_BUFFER_SIZE 512

@interface AWDLMonitor () {
    // Pipe file descriptors for internal state change communication
    int _msgfds[2];

    BOOL _exit;

    dispatch_semaphore_t _ioctlThreadExitSemaphore;
}

/// Background thread watching AWDL state
@property NSThread *ioctlThread;

/// Socket to perform ioctl to set interface flags
@property int iocfd;

/// Socket to monitor network interface changes (AF_ROUTE)
@property int rtfd;

@end

@implementation AWDLMonitor

- (instancetype)init {
    if (self = [super init]) {
        // Start off allowing AWDL to be active
        _awdlEnabled = YES;

        // Socket to monitor network interface changes
        _rtfd = socket(AF_ROUTE, SOCK_RAW, 0);
        if (_rtfd < 0) {
            os_log_error(LOG, "Error creating AF_ROUTE socket: %d", errno);
            return nil;
        }
        if (fcntl(_rtfd, F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on AF_ROUTE socket: %d", errno);
            return nil;
        }

        // Socket to perform ioctl to set interface flags
        _iocfd = socket(AF_INET, SOCK_DGRAM, 0);
        if (_iocfd < 0) {
            os_log_error(LOG, "Error creating AF_INET socket: %d", errno);
            return nil;
        }

        // Pipe for communication from main thread to ioctl thread
        if (0 != pipe(_msgfds)) {
            os_log_error(LOG, "Error creating pipe: %d", errno);
            return nil;
        }
        // Set pipe to non-blocking
        if (fcntl(_msgfds[0], F_SETFL, O_NONBLOCK) < 0) {
            os_log_error(LOG, "Error setting nonblock on pipe read fd: %d", errno);
            return nil;
        }

        // Start background thread
        _ioctlThreadExitSemaphore = dispatch_semaphore_create(0);
        _ioctlThread = [[NSThread alloc] initWithTarget:self selector:@selector(pollIoctl) object:nil];
        _ioctlThread.name = @"AWDLMonitor.pollIoctl";
        [_ioctlThread start];

        os_log(LOG, "AWDLMonitor initialized successfully");
    }
    return self;
}

/// Bring the interface up or down. Must be run only on ioctlThread.
- (void)ifconfig:(BOOL)up {
    NSAssert([NSThread currentThread] == _ioctlThread, @"ifconfig: must run on ioctlThread");

    struct ifreq ifr = {0};
    strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);

    if (ioctl(_iocfd, SIOCGIFFLAGS, &ifr) < 0) {
        os_log_error(LOG, "Error getting current interface flags: %d", errno);
        return;
    }

    if ((ifr.ifr_flags & IFF_UP) && !up) {
        // Interface is UP but we want it DOWN
        ifr.ifr_flags &= ~IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interface down: %d", errno);
        } else {
            os_log_debug(LOG, "Brought awdl0 DOWN");
        }
    } else if (!(ifr.ifr_flags & IFF_UP) && up) {
        // Interface is DOWN but we want it UP
        ifr.ifr_flags |= IFF_UP;
        if (ioctl(_iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            os_log_error(LOG, "Error bringing interface up: %d", errno);
        } else {
            os_log_debug(LOG, "Brought awdl0 UP");
        }
    }
    // else: interface is already in desired state, do nothing
}

/// Main method for the background ioctlThread.
/// Watches AWDL interface state and brings it up/down as needed.
- (void)pollIoctl {
    os_log(LOG, "pollIoctl thread started");

    BOOL quit = NO;
    BOOL enable = _awdlEnabled;

    while (!quit) {
        struct pollfd fds[] = {
            {
                .fd = _rtfd,
                .events = POLLIN,
                .revents = 0
            },
            {
                .fd = _msgfds[0],
                .events = POLLIN,
                .revents = 0
            }
        };

        // Block until we get a routing message or internal message
        if (poll(fds, 2, -1) < 1) {
            if (errno == EINTR) {
                continue;
            }
            os_log_error(LOG, "Poll error: %d", errno);
            break;
        }

        // Check for routing table changes (interface state changes)
        if (fds[0].revents) {
            os_log_debug(LOG, "Network route changed");
            int ifflag = 0;
            // Use larger buffer to handle all routing message types
            // Messages can include sockaddr structures appended after headers
            uint8_t rtmsgbuff[RTMSG_BUFFER_SIZE] = {0};

            for (ssize_t len = 0; !quit;) {
                len = read(_rtfd, rtmsgbuff, sizeof(rtmsgbuff));
                if (len < 0) {
                    if (errno == EINTR) {
                        continue;
                    } else if (errno == EAGAIN) {
                        break;
                    }
                    os_log_error(LOG, "Error reading AF_ROUTE socket: %d", errno);
                    break;  // Exit loop on unexpected errors
                }
                if (len == 0) {
                    break;  // Socket closed
                }

                // Validate message length before casting
                if (len < (ssize_t)sizeof(struct rt_msghdr)) {
                    os_log_debug(LOG, "Routing message too short: %zd bytes", len);
                    continue;
                }

                struct rt_msghdr *rtmsg = (void *)rtmsgbuff;
                if (rtmsg->rtm_type != RTM_IFINFO) {
                    continue;
                }

                // Validate we have enough data for if_msghdr
                if (len < (ssize_t)sizeof(struct if_msghdr)) {
                    os_log_debug(LOG, "IFINFO message too short: %zd bytes", len);
                    continue;
                }

                // Get interface ID for awdl0
                static int consecutiveIfFailures = 0;
                int ifidx = if_nametoindex(TARGETIFNAM);
                if (!ifidx) {
                    consecutiveIfFailures++;
                    os_log_error(LOG, "Error getting interface index for %s (%d consecutive failures)",
                                 TARGETIFNAM, consecutiveIfFailures);
                    if (consecutiveIfFailures > 10) {
                        os_log_error(LOG, "Too many failures getting interface - AWDL may not exist on this system");
                        // Don't quit, just log - interface might become available later
                    }
                    continue;
                }
                consecutiveIfFailures = 0;  // Reset on success

                struct if_msghdr *ifmsg = (void *)rtmsg;
                if (ifmsg->ifm_index != ifidx) {
                    // Not the interface we're watching
                    continue;
                }

                ifflag = ifmsg->ifm_flags;
            }

            // If AWDL was brought UP by the system but we want it DOWN
            // Use the ifconfig method to ensure proper thread-safety checks
            if ((ifflag & IFF_UP) && !enable) {
                os_log_debug(LOG, "AWDL interface was brought UP by system, bringing it back DOWN");
                [self ifconfig:NO];
            }
        }

        // Check for internal messages (enable/disable/quit)
        if (fds[1].revents) {
            char msg = 0;
            for (ssize_t len = 0; !quit;) {
                len = read(_msgfds[0], &msg, 1);
                if (len < 0) {
                    if (errno == EINTR) {
                        continue;
                    } else if (errno == EAGAIN) {
                        break;
                    }
                    os_log_error(LOG, "Error reading message pipe: %d", errno);
                    break;  // Exit loop on unexpected errors
                }
                if (len == 0) {
                    break;  // Pipe closed
                }

                switch (msg) {
                    case 'Q':
                        os_log(LOG, "Received quit message");
                        quit = YES;
                        break;
                    case 'U':
                        os_log(LOG, "Bringing AWDL interface UP (enabling)");
                        enable = YES;
                        [self ifconfig:YES];
                        break;
                    case 'D':
                        os_log(LOG, "Bringing AWDL interface DOWN (disabling)");
                        enable = NO;
                        [self ifconfig:NO];
                        break;
                    default:
                        break;
                }
            }
        }
    }

    dispatch_semaphore_signal(_ioctlThreadExitSemaphore);
    os_log(LOG, "pollIoctl thread exiting");
}

- (void)setAwdlEnabled:(BOOL)awdlEnabled {
    _awdlEnabled = awdlEnabled;
    const char *msg = awdlEnabled ? "U" : "D";
    ssize_t written = write(_msgfds[1], msg, 1);
    if (written < 0) {
        os_log_error(LOG, "Error writing to message pipe: %d", errno);
    } else if (written != 1) {
        os_log_warning(LOG, "Partial write to message pipe: wrote %zd bytes", written);
    }
}

- (void)invalidate {
    os_log(LOG, "AWDLMonitor invalidating...");

    // Send quit message to background thread
    const char *msg = "Q";
    ssize_t written = write(_msgfds[1], msg, 1);
    if (written < 0) {
        os_log_error(LOG, "Error writing quit message to pipe: %d", errno);
    }

    // Wait for background thread to exit
    dispatch_semaphore_wait(_ioctlThreadExitSemaphore, DISPATCH_TIME_FOREVER);

    os_log(LOG, "AWDLMonitor invalidated");
}

- (void)dealloc {
    if (_iocfd >= 0) close(_iocfd);
    if (_rtfd >= 0) close(_rtfd);
    if (_msgfds[0] >= 0) close(_msgfds[0]);
    if (_msgfds[1] >= 0) close(_msgfds[1]);
}

@end
