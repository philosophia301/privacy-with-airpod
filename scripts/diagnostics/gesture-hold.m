// Isolated research wrapper; upstream source stays outside the product.
#define main dockswipeOriginalMain
#ifndef DOCKSWIPE_REFERENCE
#error Define DOCKSWIPE_REFERENCE to the reviewed upstream source path
#endif
#include DOCKSWIPE_REFERENCE
#undef main
#include <signal.h>
#include <mach/mach_time.h>
static volatile sig_atomic_t interrupted = 0;
static void interruptedSignal(int signalNumber) { interrupted = signalNumber; }
int main(int argc, char **argv) {
    bool dry = false, fast = false, cancel = false;
    if (argc < 2 || argc > 5) return 2;
    for (int i=2; i<argc; i++) {
        if (!strcmp(argv[i], "--dry-run")) dry = true;
        else if (!strcmp(argv[i], "--fast")) fast = true;
        else if (!strcmp(argv[i], "--cancel")) cancel = true;
        else return 2;
    }
    char *end; double amount = strtod(argv[1], &end);
    if (*end || !isfinite(amount) || fabs(amount) < .05 || fabs(amount) > 1) return 2;
    if (!dry && !CGPreflightPostEventAccess()) { fputs("Event posting permission absent\n", stderr); return 3; }
    gDryRun = dry; gVerbose = dry;
    signal(SIGINT, interruptedSignal); signal(SIGTERM, interruptedSignal);
    printf("GESTURE BEGIN %llu %.3f\n", mach_absolute_time(), amount); fflush(stdout);
    int steps = fast ? 8 : 40;
    for (int i=0; i<steps && !interrupted; i++) {
        postDockSwipe(amount/steps, kAxisHorizontal, i ? kPhaseChanged : kPhaseBegan);
        usleep(fast ? 10000 : 12500);
    }
    printf("GESTURE HOLD %llu\n", mach_absolute_time()); fflush(stdout);
    mach_timebase_info_data_t clock; mach_timebase_info(&clock);
    uint64_t deadline = mach_absolute_time() + (uint64_t)((fast ? 0.0 : 2000000000.0) * clock.denom / clock.numer);
    while (mach_absolute_time() < deadline && !interrupted) usleep(10000);
    // 유지 후 정지한 손의 취소를 시험함. 실제 장치의 모든 종료 속도를 모사하지는 않음.
    bool shouldCancel = !fast || cancel || interrupted;
    if (shouldCancel) gLastDelta = 0;
    int phase = shouldCancel ? kPhaseCancelled : kPhaseEnded;
    postDockSwipe(0, kAxisHorizontal, phase);
    printf("GESTURE %s %llu\n", shouldCancel ? "CANCEL" : "END", mach_absolute_time()); fflush(stdout);
    usleep(200000);
    postDockSwipe(0, kAxisHorizontal, interrupted ? kPhaseCancelled : phase);
    printf("GESTURE DONE %llu interrupted=%d\n", mach_absolute_time(), interrupted); fflush(stdout);
    return interrupted ? 128 + interrupted : 0;
}
