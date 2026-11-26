#include <stdarg.h>
#include <stdio.h>

// Provide lightweight Android log stubs so Go's GOOS=android runtime
// (which uses POSIX pthread_key TLS instead of ELF initial-exec TLS,
// making it 100% compatible with HarmonyOS musl dlopen!) links purely
// against HarmonyOS musl libc.so with zero Android library dependencies.

int __android_log_write(int prio, const char* tag, const char* text) {
    (void)prio;
    if (tag && text) {
        return fprintf(stderr, "[%s] %s\n", tag, text);
    }
    return 0;
}

int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    (void)prio;
    int n = 0;
    if (tag) {
        n += fprintf(stderr, "[%s] ", tag);
    }
    if (fmt) {
        n += vfprintf(stderr, fmt, ap);
        n += fprintf(stderr, "\n");
    }
    return n;
}

int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    int n = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return n;
}
