#include <napi/native_api.h>
#include <hilog/log.h>
#include <cstring>
#include <string>
#include <ctime>

// Go cgo bridge exports (libgoout.so)
extern "C" {
char *CGoInvoke(char *req);
void CGoFree(char *p);
int goout_hev_start(const char *config_yaml, int fd);
int goout_hev_stop(void);
int goout_hev_is_running(void);
}

#define LOG_DOMAIN 0xD001
#define LOG_TAG "GoOutCore"

// invoke(jsonReq: string) => string (json response)
static napi_value Invoke(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char buf[64 * 1024] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], buf, sizeof(buf) - 1, &len);

    char *resp = CGoInvoke(buf);
    napi_value out = nullptr;
    napi_create_string_utf8(env, resp, strlen(resp), &out);
    CGoFree(resp);
    return out;
}

// hev-socks5-tunnel bridge
static napi_value StartHev(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    char yaml[4096] = {0};
    size_t len = 0;
    napi_get_value_string_utf8(env, args[0], yaml, sizeof(yaml) - 1, &len);
    int32_t fd = -1;
    napi_get_value_int32(env, args[1], &fd);

    int rc = goout_hev_start(yaml, fd);
    OH_LOG_INFO(LOG_APP, "startHev rc=%{public}d fd=%{public}d", rc, fd);
    // 给主循环一点时间初始化，然后确认还在运行（立即失败能被发现）
    struct timespec ts = {0, 200 * 1000 * 1000};
    nanosleep(&ts, nullptr);
    bool ok = (rc == 0) && goout_hev_is_running();
    napi_value out = nullptr;
    napi_get_boolean(env, ok, &out);
    return out;
}
static napi_value StopHev(napi_env env, napi_callback_info info) {
    goout_hev_stop();
    napi_value out = nullptr;
    napi_get_boolean(env, true, &out);
    return out;
}
static napi_value IsHevRunning(napi_env env, napi_callback_info info) {
    napi_value out = nullptr;
    napi_get_boolean(env, goout_hev_is_running() != 0, &out);
    return out;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"invoke", nullptr, Invoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startHev", nullptr, StartHev, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopHev", nullptr, StopHev, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isHevRunning", nullptr, IsHevRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    OH_LOG_INFO(LOG_APP, "gooutcore napi module initialized");
    return exports;
}
EXTERN_C_END

static napi_module gooutcoreModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "gooutcore",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterGoOutCoreModule(void) {
    napi_module_register(&gooutcoreModule);
}
