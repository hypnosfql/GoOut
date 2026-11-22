#include <stdio.h>
#include <stdarg.h>
#include <android/log.h>
int __android_log_write(int prio, const char* tag, const char* text) {
    fprintf(stderr, "[%d]%s: %s\n", prio, tag ? tag : "", text ? text : "");
    return 0;
}
int __android_log_vprint(int prio, const char* tag, const char* fmt, va_list ap) {
    fprintf(stderr, "[%d]%s: ", prio, tag ? tag : "");
    return vfprintf(stderr, fmt, ap);
}
int __android_log_print(int prio, const char* tag, const char* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    int r = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return r;
}
