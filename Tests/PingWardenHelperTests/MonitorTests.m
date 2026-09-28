// Isolated tests for the production privileged-helper monitor.
// socket(), ioctl(), poll(), and if_nametoindex() are replaced before importing
// the implementation. The fixture can only operate on a local datagram
// socketpair, /dev/null, and a marker file in a temporary directory.
#import <Foundation/Foundation.h>
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
#import <stdarg.h>
#import <pthread.h>

static pthread_mutex_t fixtureLock = PTHREAD_MUTEX_INITIALIZER;
static short fixtureFlags;
static int fixtureReadCount;
static int fixtureWriteCount;
static int fixtureFailReadAt;
static BOOL fixtureFailWrites;
static BOOL fixtureIgnoreWrites;
static unsigned fixtureIODelayMicroseconds;
static int fixtureActiveIO;
static int fixturePeakIO;
static int fixtureRouteWriteFD = -1;
static int fixturePollFailures;
static char fixtureMarkerPath[PATH_MAX];

static int fixtureSocket(int domain, int type, int protocol) {
    (void)type;
    (void)protocol;
    if (domain == AF_ROUTE) {
        // A datagram pair keeps message boundaries like the kernel's route
        // socket and accepts SO_RCVBUF.
        int fds[2];
        if (socketpair(AF_UNIX, SOCK_DGRAM, 0, fds) != 0) return -1;
        pthread_mutex_lock(&fixtureLock);
        fixtureRouteWriteFD = fds[1];
        pthread_mutex_unlock(&fixtureLock);
        return fds[0];
    }
    if (domain == AF_INET) return open("/dev/null", O_RDONLY);
    errno = EAFNOSUPPORT;
    return -1;
}

static int fixtureIoctl(int fd, unsigned long request, ...) {
    (void)fd;
    va_list arguments;
    va_start(arguments, request);
    struct ifreq *interface = va_arg(arguments, struct ifreq *);
    va_end(arguments);

    pthread_mutex_lock(&fixtureLock);
    fixtureActiveIO++;
    fixturePeakIO = MAX(fixturePeakIO, fixtureActiveIO);
    unsigned delay = fixtureIODelayMicroseconds;
    pthread_mutex_unlock(&fixtureLock);
    if (delay > 0) usleep(delay);

    int result = 0;
    pthread_mutex_lock(&fixtureLock);
    if (request == SIOCGIFFLAGS) {
        fixtureReadCount++;
        if (fixtureFailReadAt == fixtureReadCount) {
            result = -1;
        } else {
            interface->ifr_flags = fixtureFlags;
        }
    } else if (request == SIOCSIFFLAGS) {
        fixtureWriteCount++;
        if (fixtureFailWrites) {
            result = -1;
        } else if (!fixtureIgnoreWrites) {
            fixtureFlags = interface->ifr_flags;
        }
    } else {
        result = -1;
    }
    fixtureActiveIO--;
    pthread_mutex_unlock(&fixtureLock);
    if (result < 0) errno = EIO;
    return result;
}

static unsigned fixtureInterfaceIndex(const char *name) {
    return strcmp(name, "awdl0") == 0 ? 7 : 0;
}

static int fixturePoll(struct pollfd *fds, nfds_t count, int timeout) {
    pthread_mutex_lock(&fixtureLock);
    BOOL fail = fixturePollFailures > 0;
    if (fail) fixturePollFailures--;
    pthread_mutex_unlock(&fixtureLock);
    if (fail) {
        errno = ENOMEM;
        return -1;
    }
    return poll(fds, count, timeout);
}

#define socket fixtureSocket
#define ioctl fixtureIoctl
#define if_nametoindex fixtureInterfaceIndex
#define poll fixturePoll
#import "../../PingWarden/PingWardenHelper/PingWardenMonitor.m"
#undef socket
#undef ioctl
#undef if_nametoindex
#undef poll

static int checkCount;
static int failureCount;
#define CHECK(expression) do { \
    checkCount++; \
    if (!(expression)) { \
        failureCount++; \
        fprintf(stderr, "%s:%d: failed: %s\n", __func__, __LINE__, #expression); \
    } \
} while (0)

static void closeFixtureRouteWriter(void) {
    pthread_mutex_lock(&fixtureLock);
    int fd = fixtureRouteWriteFD;
    fixtureRouteWriteFD = -1;
    pthread_mutex_unlock(&fixtureLock);
    if (fd >= 0) close(fd);
}

static PingWardenMonitor *makeMonitorWithMarker(short initialFlags, BOOL markerPresent) {
    if (markerPresent) {
        int fd = open(fixtureMarkerPath, O_WRONLY | O_CREAT, 0644);
        if (fd < 0) exit(2);
        close(fd);
    } else {
        unlink(fixtureMarkerPath);
    }
    pthread_mutex_lock(&fixtureLock);
    fixtureFlags = initialFlags;
    fixtureReadCount = 0;
    fixtureWriteCount = 0;
    fixtureFailReadAt = 0;
    fixtureFailWrites = NO;
    fixtureIgnoreWrites = NO;
    fixtureIODelayMicroseconds = 0;
    fixtureActiveIO = 0;
    fixturePeakIO = 0;
    fixturePollFailures = 0;
    pthread_mutex_unlock(&fixtureLock);
    PingWardenMonitor *monitor = [[PingWardenMonitor alloc]
        initWithLoweredMarkerPath:@(fixtureMarkerPath)];
    if (!monitor) {
        fprintf(stderr, "Unable to initialize isolated monitor fixture\n");
        exit(2);
    }
    return monitor;
}

static PingWardenMonitor *makeMonitor(short initialFlags) {
    return makeMonitorWithMarker(initialFlags, NO);
}

static void finishMonitor(PingWardenMonitor *monitor) {
    [monitor invalidate];
    closeFixtureRouteWriter();
}

static short actualFlags(void) {
    pthread_mutex_lock(&fixtureLock);
    short value = fixtureFlags;
    pthread_mutex_unlock(&fixtureLock);
    return value;
}

static int writeCount(void) {
    pthread_mutex_lock(&fixtureLock);
    int value = fixtureWriteCount;
    pthread_mutex_unlock(&fixtureLock);
    return value;
}

static void setActualFlags(short flags) {
    pthread_mutex_lock(&fixtureLock);
    fixtureFlags = flags;
    pthread_mutex_unlock(&fixtureLock);
}

static void failReadAfter(int reads) {
    pthread_mutex_lock(&fixtureLock);
    fixtureFailReadAt = fixtureReadCount + reads;
    pthread_mutex_unlock(&fixtureLock);
}

static void setWriteFailure(BOOL enabled) {
    pthread_mutex_lock(&fixtureLock);
    fixtureFailWrites = enabled;
    pthread_mutex_unlock(&fixtureLock);
}

static int readCount(void) {
    pthread_mutex_lock(&fixtureLock);
    int value = fixtureReadCount;
    pthread_mutex_unlock(&fixtureLock);
    return value;
}

static BOOL markerExists(void) {
    return access(fixtureMarkerPath, F_OK) == 0;
}

static void removeMarker(void) {
    unlink(fixtureMarkerPath);
}

/// Send one datagram on the fixture route socket. Its content is irrelevant:
/// the monitor treats any route message as a prompt to re-read awdl0.
static void sendRouteMessage(void) {
    pthread_mutex_lock(&fixtureLock);
    int fd = fixtureRouteWriteFD;
    pthread_mutex_unlock(&fixtureLock);
    const uint8_t message[32] = {0};
    if (fd >= 0 && write(fd, message, sizeof(message)) < 0) {
        fprintf(stderr, "Unable to write fixture route message\n");
        exit(2);
    }
}

static BOOL waitUntil(BOOL (^condition)(void), double seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition()) {
        if ([deadline timeIntervalSinceNow] < 0) return NO;
        usleep(2000);
    }
    return YES;
}

static void testSuccessfulChanges(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP | IFF_BROADCAST);
    CHECK(monitor.awdlEnabled);
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(!(actualFlags() & IFF_UP));
    CHECK(actualFlags() & IFF_BROADCAST);
    CHECK(!monitor.awdlEnabled);
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(actualFlags() & IFF_UP);
    CHECK(monitor.awdlEnabled);
    CHECK(writeCount() == 2);
    finishMonitor(monitor);
}

static void testAlreadyCorrectState(void) {
    PingWardenMonitor *monitor = makeMonitor(0);
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(!monitor.awdlEnabled);
    CHECK(writeCount() == 0);
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(writeCount() == 0);
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(writeCount() == 1);
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(writeCount() == 1);
    finishMonitor(monitor);
}

static void testInitialReadFailure(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    failReadAfter(1);
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(writeCount() == 0);
    CHECK(actualFlags() & IFF_UP);
    CHECK(monitor.awdlEnabled);
    // A rejected enable must not leave blocking armed for later route events.
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == 0);
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

static void testWriteFailure(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    setWriteFailure(YES);
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(writeCount() == 1);
    CHECK(actualFlags() & IFF_UP);
    CHECK(monitor.awdlEnabled);
    setWriteFailure(NO);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == 1);
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

static void testReadbackFailure(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    failReadAfter(2);
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(writeCount() == 1);
    CHECK(!(actualFlags() & IFF_UP));
    // The ioctl applied, but failed verification cannot publish protection.
    CHECK(monitor.awdlEnabled);
    setActualFlags(IFF_UP);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == 1);
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

static void testReadbackMismatch(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    pthread_mutex_lock(&fixtureLock);
    fixtureIgnoreWrites = YES;
    pthread_mutex_unlock(&fixtureLock);
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(writeCount() == 1);
    CHECK(actualFlags() & IFF_UP);
    CHECK(monitor.awdlEnabled);
    pthread_mutex_lock(&fixtureLock);
    fixtureIgnoreWrites = NO;
    pthread_mutex_unlock(&fixtureLock);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == 1);
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

static void testFailedDisablePreservesBlocking(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    setWriteFailure(YES);
    CHECK(![monitor setAwdlEnabled:YES]);
    CHECK(!(actualFlags() & IFF_UP));
    CHECK(!monitor.awdlEnabled);
    setWriteFailure(NO);
    setActualFlags(IFF_UP);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(!(actualFlags() & IFF_UP));
    CHECK([monitor getInterventionCount] == 1);
    finishMonitor(monitor);
}

static void testStateReadReflectsFailureAndActualFlags(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(!monitor.awdlEnabled);
    failReadAfter(1);
    CHECK(monitor.awdlEnabled);
    CHECK(!monitor.awdlEnabled);
    // A read in the instant macOS re-raised awdl0 enforces first and reports
    // the state the helper holds, not the transient.
    setActualFlags(IFF_UP);
    CHECK(!monitor.awdlEnabled);
    CHECK(!(actualFlags() & IFF_UP));
    CHECK([monitor getInterventionCount] == 1);
    // When that enforcement cannot take, the read stays honest.
    setActualFlags(IFF_UP);
    setWriteFailure(YES);
    CHECK(monitor.awdlEnabled);
    CHECK(actualFlags() & IFF_UP);
    setWriteFailure(NO);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(!monitor.awdlEnabled);
    finishMonitor(monitor);
}

static void testRouteEnforcementAttempts(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    // An event while protection is off cannot block or count an intervention.
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == 0);
    CHECK([monitor getInterventionCount] == 0);
    CHECK([monitor setAwdlEnabled:NO]);
    [monitor handleInterfaceFlags:0];
    CHECK([monitor getInterventionCount] == 0);
    setActualFlags(IFF_UP);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(!(actualFlags() & IFF_UP));
    CHECK([monitor getInterventionCount] == 1);
    setActualFlags(IFF_UP);
    setWriteFailure(YES);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(actualFlags() & IFF_UP);
    CHECK([monitor getInterventionCount] == 2); // Counts attempts, by contract.
    // The state read retries enforcement, which fails again and counts.
    CHECK(monitor.awdlEnabled);
    CHECK([monitor getInterventionCount] == 3);
    setWriteFailure(NO);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(!(actualFlags() & IFF_UP));
    CHECK([monitor getInterventionCount] == 4);
    CHECK(!monitor.awdlEnabled);
    [monitor resetInterventionCount];
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

typedef struct {
    __unsafe_unretained PingWardenMonitor *monitor;
    atomic_bool *results;
} ConcurrentCommandContext;

static void runConcurrentCommand(void *rawContext, size_t index) {
    ConcurrentCommandContext *context = rawContext;
    @autoreleasepool {
        atomic_store(&context->results[index], [context->monitor setAwdlEnabled:index % 2 == 0]);
    }
}

static void testConcurrentCommandsAreSerialized(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    pthread_mutex_lock(&fixtureLock);
    fixtureIODelayMicroseconds = 500;
    pthread_mutex_unlock(&fixtureLock);
    const size_t commandCount = 80;
    // A plain context struct and atomic result slots keep ThreadSanitizer's
    // view limited to the monitor itself, not the fixture's block copies.
    ConcurrentCommandContext context = {
        .monitor = monitor,
        .results = calloc(commandCount, sizeof(atomic_bool)),
    };
    if (!context.results) exit(2);
    dispatch_apply_f(commandCount, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0),
                     &context, runConcurrentCommand);
    for (size_t index = 0; index < commandCount; index++) CHECK(atomic_load(&context.results[index]));
    free(context.results);
    pthread_mutex_lock(&fixtureLock);
    int peak = fixturePeakIO;
    pthread_mutex_unlock(&fixtureLock);
    CHECK(peak == 1);
    CHECK(monitor.awdlEnabled == !!(actualFlags() & IFF_UP));
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(!monitor.awdlEnabled);
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(monitor.awdlEnabled);
    finishMonitor(monitor);
}

static void testShutdownRejectsNewCommands(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    [monitor invalidate];
    int writesBefore = writeCount();
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(![monitor setAwdlEnabled:YES]);
    CHECK(monitor.awdlEnabled);
    setActualFlags(IFF_UP);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(writeCount() == writesBefore);
    CHECK([monitor getInterventionCount] == 0);
    closeFixtureRouteWriter();
}

static void testShutdownDuringCommandDoesNotDeadlock(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    pthread_mutex_lock(&fixtureLock);
    fixtureIODelayMicroseconds = 20000;
    pthread_mutex_unlock(&fixtureLock);
    dispatch_group_t group = dispatch_group_create();
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [monitor setAwdlEnabled:NO];
    });
    BOOL started = NO;
    for (int attempt = 0; attempt < 1000; attempt++) {
        pthread_mutex_lock(&fixtureLock);
        started = fixtureActiveIO > 0;
        pthread_mutex_unlock(&fixtureLock);
        if (started) break;
        usleep(1000);
    }
    CHECK(started);
    dispatch_group_async(group, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [monitor invalidate];
    });
    if (dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0) {
        fprintf(stderr, "Shutdown and interface operation deadlocked\n");
        exit(2);
    }
    CHECK(![monitor setAwdlEnabled:NO]);
    CHECK(monitor.awdlEnabled);
    closeFixtureRouteWriter();
}

static void testRouteWakeupReconcilesActualFlags(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    // macOS raises awdl0 and the message saying so is dropped. Any later
    // route message, about any interface, must still bring it down.
    setActualFlags(IFF_UP);
    sendRouteMessage();
    CHECK(waitUntil(^{ return (BOOL)!(actualFlags() & IFF_UP); }, 2.0));
    CHECK([monitor getInterventionCount] == 1);
    CHECK(!monitor.awdlEnabled);
    finishMonitor(monitor);
}

static void testPeriodicReconcileWithoutMessages(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    monitor.reconcileIntervalMs = 30;
    CHECK([monitor setAwdlEnabled:NO]);
    setActualFlags(IFF_UP);
    CHECK(waitUntil(^{ return (BOOL)!(actualFlags() & IFF_UP); }, 2.0));
    finishMonitor(monitor);
}

static void testFailedEnforcementRetriesSoon(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    monitor.reconcileIntervalMs = 60000;
    monitor.retryIntervalMs = 20;
    CHECK([monitor setAwdlEnabled:NO]);
    setWriteFailure(YES);
    setActualFlags(IFF_UP);
    sendRouteMessage();
    CHECK(waitUntil(^{ return (BOOL)([monitor getInterventionCount] >= 1); }, 2.0));
    setWriteFailure(NO);
    // No further route message: only the short retry timeout can recover.
    CHECK(waitUntil(^{ return (BOOL)!(actualFlags() & IFF_UP); }, 2.0));
    finishMonitor(monitor);
}

static void testIdleMonitorIgnoresRouteMessages(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    monitor.reconcileIntervalMs = 10;
    int readsBefore = readCount();
    for (int message = 0; message < 5; message++) sendRouteMessage();
    usleep(100 * 1000);
    // Allowing AWDL: no route wakeups, no periodic checks, no interface I/O.
    CHECK(readCount() == readsBefore);
    CHECK(writeCount() == 0);
    finishMonitor(monitor);
}

static void testPollErrorsDoNotStopEnforcement(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    pthread_mutex_lock(&fixtureLock);
    fixturePollFailures = 2;
    pthread_mutex_unlock(&fixtureLock);
    // The wake from this command runs the poller into the injected failures.
    CHECK([monitor setAwdlEnabled:NO]);
    setActualFlags(IFF_UP);
    sendRouteMessage();
    CHECK(waitUntil(^{ return (BOOL)!(actualFlags() & IFF_UP); }, 3.0));
    CHECK(!monitor.awdlEnabled);
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(actualFlags() & IFF_UP);
    finishMonitor(monitor);
}

static void testLoweredMarkerLifecycle(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK(!markerExists());
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(markerExists());
    CHECK([monitor setAwdlEnabled:YES]);
    CHECK(!markerExists());
    finishMonitor(monitor);
}

static void testExitLeavesInterfaceTheHelperDidNotLower(void) {
    PingWardenMonitor *monitor = makeMonitor(0);
    // Blocking an interface that macOS already had down (Wi-Fi off, for
    // example) lowers nothing, so exit must not raise it.
    CHECK([monitor setAwdlEnabled:NO]);
    CHECK(!markerExists());
    [monitor invalidate];
    [monitor restoreInterfaceIfLowered];
    CHECK(!(actualFlags() & IFF_UP));
    CHECK(writeCount() == 0);
    closeFixtureRouteWriter();
}

static void testExitRestoresInterfaceTheHelperLowered(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    [monitor invalidate];
    [monitor restoreInterfaceIfLowered];
    CHECK(actualFlags() & IFF_UP);
    CHECK(!markerExists());
    closeFixtureRouteWriter();
}

static void testFailedExitRestoreKeepsMarker(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    CHECK([monitor setAwdlEnabled:NO]);
    [monitor invalidate];
    setWriteFailure(YES);
    [monitor restoreInterfaceIfLowered];
    CHECK(!(actualFlags() & IFF_UP));
    // The next helper instance retries from the marker.
    CHECK(markerExists());
    setWriteFailure(NO);
    closeFixtureRouteWriter();
    removeMarker();
}

static void testStartupRestoresAfterUncleanExit(void) {
    PingWardenMonitor *monitor = makeMonitorWithMarker(0, YES);
    CHECK(actualFlags() & IFF_UP);
    CHECK(writeCount() == 1);
    CHECK(!markerExists());
    CHECK(monitor.awdlEnabled);
    finishMonitor(monitor);
}

static void testStartupWithoutMarkerLeavesInterfaceAlone(void) {
    PingWardenMonitor *monitor = makeMonitor(0);
    CHECK(!(actualFlags() & IFF_UP));
    CHECK(writeCount() == 0);
    finishMonitor(monitor);
}

int main(void) {
    @autoreleasepool {
        char directory[] = "/tmp/pingwarden-helper-marker.XXXXXX";
        if (!mkdtemp(directory)) exit(2);
        snprintf(fixtureMarkerPath, sizeof(fixtureMarkerPath), "%s/awdl-lowered", directory);

        testSuccessfulChanges();
        testAlreadyCorrectState();
        testInitialReadFailure();
        testWriteFailure();
        testReadbackFailure();
        testReadbackMismatch();
        testFailedDisablePreservesBlocking();
        testStateReadReflectsFailureAndActualFlags();
        testRouteEnforcementAttempts();
        testConcurrentCommandsAreSerialized();
        testShutdownRejectsNewCommands();
        testShutdownDuringCommandDoesNotDeadlock();
        testRouteWakeupReconcilesActualFlags();
        testPeriodicReconcileWithoutMessages();
        testFailedEnforcementRetriesSoon();
        testIdleMonitorIgnoresRouteMessages();
        testPollErrorsDoNotStopEnforcement();
        testLoweredMarkerLifecycle();
        testExitLeavesInterfaceTheHelperDidNotLower();
        testExitRestoresInterfaceTheHelperLowered();
        testFailedExitRestoreKeepsMarker();
        testStartupRestoresAfterUncleanExit();
        testStartupWithoutMarkerLeavesInterfaceAlone();

        unlink(fixtureMarkerPath);
        rmdir(directory);
        printf("Helper monitor tests: %d checks, %d failures\n", checkCount, failureCount);
        return failureCount == 0 ? 0 : 1;
    }
}
