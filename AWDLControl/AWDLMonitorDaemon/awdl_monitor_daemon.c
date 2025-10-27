/*
 * AWDL Monitor Daemon
 *
 * This daemon monitors the awdl0 interface using AF_ROUTE sockets
 * and immediately brings it down the moment it goes up.
 *
 * Based on awdlkiller by jamestut (https://github.com/jamestut/awdlkiller)
 * This provides the same instant response time with 0% CPU when idle.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <unistd.h>
#include <poll.h>
#include <errno.h>
#include <err.h>
#include <fcntl.h>
#include <syslog.h>
#include <signal.h>

#define TARGETIFNAM "awdl0"
#define DAEMON_NAME "com.awdlcontrol.daemon"

// Buffer for routing messages
uint8_t rtmsgbuff[sizeof(struct rt_msghdr) + sizeof(struct if_msghdr)];

// Signal handling for graceful shutdown
volatile sig_atomic_t should_exit = 0;

void signal_handler(int signum) {
    syslog(LOG_INFO, "Received signal %d, shutting down", signum);
    should_exit = 1;
}

void setup_signal_handlers() {
    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = signal_handler;
    sigemptyset(&sa.sa_mask);

    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
}

int main(int argc __attribute__((unused)), char *argv[] __attribute__((unused))) {
    // Open syslog for logging
    openlog(DAEMON_NAME, LOG_PID | LOG_CONS, LOG_DAEMON);
    syslog(LOG_INFO, "Starting AWDL Monitor Daemon");

    // Set up signal handlers for graceful shutdown
    setup_signal_handlers();

    // Check if running as root
    if (getuid() != 0) {
        // Try to escalate to root
        if (setuid(0) < 0) {
            syslog(LOG_ERR, "Error escalating to root. Run as root or set setuid bit.");
            errx(1, "Error escalating permission to root. Either run this daemon as root"
                " or set setuid bit with root permission.");
        }
    }

    // Get interface index for awdl0
    int ifidx = if_nametoindex(TARGETIFNAM);
    if (!ifidx) {
        syslog(LOG_ERR, "Error getting interface index for %s: %s", TARGETIFNAM, strerror(errno));
        err(1, "Error getting interface name");
    }
    syslog(LOG_INFO, "Monitoring interface %s (index: %d)", TARGETIFNAM, ifidx);

    // Create AF_ROUTE socket to monitor network interface changes
    // This socket receives routing messages from the kernel in real-time
    int rtfd = socket(AF_ROUTE, SOCK_RAW, 0);
    if (rtfd < 0) {
        syslog(LOG_ERR, "Error creating AF_ROUTE socket: %s", strerror(errno));
        err(1, "Error creating AF_ROUTE socket");
    }

    // Set socket to non-blocking mode
    if (fcntl(rtfd, F_SETFL, O_NONBLOCK) < 0) {
        syslog(LOG_ERR, "Error setting nonblock on AF_ROUTE socket: %s", strerror(errno));
        err(1, "Error setting nonblock on AF_ROUTE socket");
    }

    // Create socket for ioctl operations to set interface flags
    int iocfd = socket(AF_INET, SOCK_DGRAM, 0);
    if (iocfd < 0) {
        syslog(LOG_ERR, "Error creating AF_INET socket: %s", strerror(errno));
        err(1, "Error creating AF_INET socket");
    }

    struct ifreq ifr = {0};
    strlcpy(ifr.ifr_name, TARGETIFNAM, IFNAMSIZ);

    // Bring AWDL down immediately on daemon startup
    syslog(LOG_INFO, "Bringing %s down on startup", TARGETIFNAM);
    if (ioctl(iocfd, SIOCGIFFLAGS, &ifr) < 0) {
        syslog(LOG_ERR, "Error getting initial flags: %s", strerror(errno));
        err(1, "Error getting initial flags");
    }

    if (ifr.ifr_flags & IFF_UP) {
        ifr.ifr_flags &= ~IFF_UP;
        if (ioctl(iocfd, SIOCSIFFLAGS, &ifr) < 0) {
            syslog(LOG_ERR, "Error bringing interface down on startup: %s", strerror(errno));
            err(1, "Error initial disable interface");
        }
        syslog(LOG_INFO, "Successfully brought %s down on startup", TARGETIFNAM);
    } else {
        syslog(LOG_INFO, "%s already down on startup", TARGETIFNAM);
    }

    // Set up poll structure for AF_ROUTE socket
    struct pollfd prt;
    prt.fd = rtfd;
    prt.events = POLLIN;

    syslog(LOG_INFO, "Entering monitoring loop (event-driven, 0%% CPU idle)");

    // Main event loop - blocks on poll() until interface changes
    // This is the key to 0% CPU usage when idle
    while (!should_exit) {
        // poll() blocks until data is available or timeout
        // Using -1 timeout means infinite wait (0% CPU)
        int poll_result = poll(&prt, 1, -1);

        if (poll_result < 0) {
            if (errno == EINTR) {
                // Interrupted by signal, check should_exit
                continue;
            }
            syslog(LOG_ERR, "Error polling AF_ROUTE socket: %s", strerror(errno));
            err(1, "Error polling AF_ROUTE socket");
        }

        // Read all queued routing messages
        // Take the final flag value and apply it once
        int ifflag = 0;
        int got_message = 0;

        for(;;) {
            ssize_t len = read(rtfd, rtmsgbuff, sizeof(rtmsgbuff));

            if (len < 0) {
                if (errno == EINTR) {
                    continue;
                } else if (errno == EAGAIN) {
                    // No more messages to read
                    break;
                }
                syslog(LOG_ERR, "Error reading AF_ROUTE socket: %s", strerror(errno));
                err(1, "Error reading AF_ROUTE socket");
            }

            // Parse the routing message
            struct rt_msghdr *rtmsg = (void *)rtmsgbuff;

            // We only care about RTM_IFINFO messages (interface info changes)
            if (rtmsg->rtm_type != RTM_IFINFO) {
                continue;
            }

            struct if_msghdr *ifmsg = (void *)rtmsg;

            // Check if this message is for our target interface
            if (ifmsg->ifm_index != ifidx) {
                // Not the interface we're monitoring
                continue;
            }

            // Got a message for awdl0
            ifflag = ifmsg->ifm_flags;
            got_message = 1;
        }

        // If we received interface flag changes and AWDL is UP, bring it DOWN
        if (got_message && (ifflag & IFF_UP)) {
            syslog(LOG_NOTICE, "⚠️  AWDL is UP! Bringing it down immediately...");

            // Clear the UP flag
            ifr.ifr_flags = ifflag & ~IFF_UP;

            if (ioctl(iocfd, SIOCSIFFLAGS, &ifr) < 0) {
                syslog(LOG_ERR, "❌ Error turning down interface: %s", strerror(errno));
                err(1, "Error turning down interface");
            }

            syslog(LOG_INFO, "✅ Successfully brought %s down (response time: <1ms)", TARGETIFNAM);
        }
    }

    // Cleanup on shutdown
    syslog(LOG_INFO, "Shutting down gracefully");
    close(iocfd);
    close(rtfd);
    closelog();

    return 0;
}
