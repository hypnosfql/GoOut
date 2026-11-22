/* hev-socks5-tunnel 线程封装：主循环阻塞，放独立 pthread 运行 */
#include <pthread.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#include "hev-main.h"

typedef struct _ThreadData ThreadData;

struct _ThreadData {
    char *config;
    int fd;
};

static pthread_t work_thread;
static atomic_int is_running = 0;

static void *thread_handler(void *data) {
    ThreadData *td = (ThreadData *)data;
    atomic_store(&is_running, 1);
    hev_socks5_tunnel_main_from_str((const unsigned char *)td->config,
                                    (unsigned int)strlen(td->config), td->fd);
    atomic_store(&is_running, 0);
    free(td->config);
    free(td);
    return NULL;
}

int goout_hev_start(const char *config_yaml, int fd) {
    if (atomic_load(&is_running)) {
        return -1;
    }
    ThreadData *td = (ThreadData *)malloc(sizeof(ThreadData));
    if (!td) {
        return -2;
    }
    td->config = strdup(config_yaml);
    td->fd = fd;
    if (pthread_create(&work_thread, NULL, thread_handler, td) != 0) {
        free(td->config);
        free(td);
        return -3;
    }
    pthread_detach(work_thread);
    return 0;
}

int goout_hev_stop(void) {
    if (!atomic_load(&is_running)) {
        return 0;
    }
    hev_socks5_tunnel_quit();
    return 0;
}

int goout_hev_is_running(void) {
    return atomic_load(&is_running);
}

void goout_hev_stats(unsigned long *tx_packets, unsigned long *tx_bytes,
                     unsigned long *rx_packets, unsigned long *rx_bytes) {
    size_t tp = 0, tb = 0, rp = 0, rb = 0;
    hev_socks5_tunnel_stats(&tp, &tb, &rp, &rb);
    *tx_packets = tp;
    *tx_bytes = tb;
    *rx_packets = rp;
    *rx_bytes = rb;
}
