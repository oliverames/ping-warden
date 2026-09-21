// Isolated tests for the production privileged-helper monitor.
// socket(), ioctl(), and if_nametoindex() are replaced before importing the
// implementation. The fixture can only operate on pipes and /dev/null.
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

static int fixtureSocket(int domain, int type, int protocol) {
    (void)type;
    (void)protocol;
    if (domain == AF_ROUTE) {
        int fds[2];
        if (pipe(fds) != 0) return -1;
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

#define socket fixtureSocket
#define ioctl fixtureIoctl
#define if_nametoindex fixtureInterfaceIndex
#import "../../PingWarden/PingWardenHelper/PingWardenMonitor.m"
#undef socket
#undef ioctl
#undef if_nametoindex

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

static PingWardenMonitor *makeMonitor(short initialFlags) {
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
    pthread_mutex_unlock(&fixtureLock);
    PingWardenMonitor *monitor = [PingWardenMonitor new];
    if (!monitor) {
        fprintf(stderr, "Unable to initialize isolated monitor fixture\n");
        exit(2);
    }
    return monitor;
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
    setActualFlags(IFF_UP);
    CHECK(monitor.awdlEnabled);
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
    CHECK(monitor.awdlEnabled);
    setWriteFailure(NO);
    [monitor handleInterfaceFlags:IFF_UP];
    CHECK(!(actualFlags() & IFF_UP));
    CHECK([monitor getInterventionCount] == 3);
    CHECK(!monitor.awdlEnabled);
    [monitor resetInterventionCount];
    CHECK([monitor getInterventionCount] == 0);
    finishMonitor(monitor);
}

static void testConcurrentCommandsAreSerialized(void) {
    PingWardenMonitor *monitor = makeMonitor(IFF_UP);
    pthread_mutex_lock(&fixtureLock);
    fixtureIODelayMicroseconds = 500;
    pthread_mutex_unlock(&fixtureLock);
    const size_t commandCount = 80;
    BOOL *results = calloc(commandCount, sizeof(BOOL));
    if (!results) exit(2);
    dispatch_apply(commandCount, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^(size_t index) {
        @autoreleasepool {
            results[index] = [monitor setAwdlEnabled:index % 2 == 0];
        }
    });
    for (size_t index = 0; index < commandCount; index++) CHECK(results[index]);
    free(results);
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

int main(void) {
    @autoreleasepool {
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
        printf("Helper monitor tests: %d checks, %d failures\n", checkCount, failureCount);
        return failureCount == 0 ? 0 : 1;
    }
}
