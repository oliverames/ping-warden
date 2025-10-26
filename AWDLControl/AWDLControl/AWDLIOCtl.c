#include <sys/types.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <string.h>
#include <unistd.h>

/// Get interface flags using ioctl (much faster than ifconfig)
/// Returns -1 on error, flags value on success
int awdl_get_flags(const char *ifname, int *flags) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return -1;
    }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strlcpy(ifr.ifr_name, ifname, IFNAMSIZ);

    if (ioctl(sock, SIOCGIFFLAGS, &ifr) < 0) {
        close(sock);
        return -1;
    }

    *flags = ifr.ifr_flags;
    close(sock);
    return 0;
}

/// Set interface flags using ioctl
/// Returns -1 on error, 0 on success
int awdl_set_flags(const char *ifname, int flags) {
    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return -1;
    }

    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    strlcpy(ifr.ifr_name, ifname, IFNAMSIZ);
    ifr.ifr_flags = flags;

    if (ioctl(sock, SIOCSIFFLAGS, &ifr) < 0) {
        close(sock);
        return -1;
    }

    close(sock);
    return 0;
}

/// Bring interface down by clearing IFF_UP flag
/// Returns -1 on error, 0 on success
int awdl_bring_down(const char *ifname) {
    int flags;
    if (awdl_get_flags(ifname, &flags) < 0) {
        return -1;
    }

    // Clear IFF_UP flag
    flags &= ~IFF_UP;

    return awdl_set_flags(ifname, flags);
}

/// Bring interface up by setting IFF_UP flag
/// Returns -1 on error, 0 on success
int awdl_bring_up(const char *ifname) {
    int flags;
    if (awdl_get_flags(ifname, &flags) < 0) {
        return -1;
    }

    // Set IFF_UP flag
    flags |= IFF_UP;

    return awdl_set_flags(ifname, flags);
}

/// Check if interface is up
/// Returns 1 if up, 0 if down, -1 on error
int awdl_is_up(const char *ifname) {
    int flags;
    if (awdl_get_flags(ifname, &flags) < 0) {
        return -1;
    }

    return (flags & IFF_UP) ? 1 : 0;
}
