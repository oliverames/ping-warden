#ifndef AWDLIOCtl_h
#define AWDLIOCtl_h

#include <stdio.h>

/// Get interface flags using ioctl
/// Returns -1 on error, flags value on success
int awdl_get_flags(const char *ifname, int *flags);

/// Set interface flags using ioctl
/// Returns -1 on error, 0 on success
int awdl_set_flags(const char *ifname, int flags);

/// Bring interface down by clearing IFF_UP flag
/// Returns -1 on error, 0 on success
int awdl_bring_down(const char *ifname);

/// Bring interface up by setting IFF_UP flag
/// Returns -1 on error, 0 on success
int awdl_bring_up(const char *ifname);

/// Check if interface is up
/// Returns 1 if up, 0 if down, -1 on error
int awdl_is_up(const char *ifname);

#endif /* AWDLIOCtl_h */
