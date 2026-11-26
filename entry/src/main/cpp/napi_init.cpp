#include "napi/native_api.h"
#include "hilog/log.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <dlfcn.h>
#include <map>
#include <mutex>
#include <string>

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x3200
#define LOG_TAG "TizLinkNative"

namespace {

typedef int (*ProtectFn)(int fd);
typedef char* (*SetupFn)(char* homeDir);
typedef void (*SetProtectCallbackFn)(ProtectFn fn);
typedef char* (*StartTunFn)(int tunFd, char* configYaml);
typedef void (*StopFn)();
typedef int (*IsRunningFn)();
typedef void (*SetLogLevelFn)(char* level);
typedef void (*NotifyNetworkChangeFn)();
typedef char* (*GetTrafficFn)();
typedef char* (*GetVersionFn)();
typedef char* (*GetLogsFn)();
typedef void (*ClearLogsFn)();
typedef void (*FreeStringFn)(char* ptr);

struct MihomoApi {
    void* handle = nullptr;
    SetupFn setup = nullptr;
    SetProtectCallbackFn setProtectCallback = nullptr;
    StartTunFn startTun = nullptr;
    StopFn stop = nullptr;
    IsRunningFn isRunning = nullptr;
    SetLogLevelFn setLogLevel = nullptr;
    NotifyNetworkChangeFn notifyNetworkChange = nullptr;
    GetTrafficFn getTraffic = nullptr;
    GetVersionFn getVersion = nullptr;
    GetLogsFn getLogs = nullptr;
    ClearLogsFn clearLogs = nullptr;
    FreeStringFn freeString = nullptr;
    std::string loadError;
};

MihomoApi g_api;
std::mutex g_apiMutex;

// Socket protection bridge: Go goroutine -> ThreadsafeFunction -> ArkTS vpnConnection.protect(fd)
std::mutex g_protectMutex;
napi_threadsafe_function g_protectTsfn = nullptr;
std::atomic<bool> g_processProtected{false};
std::atomic<int64_t> g_nextReqId{1};

struct ProtectRequest {
    int64_t reqId;
    int fd;
    bool done = false;
    bool ok = true;
    std::mutex mu;
    std::condition_variable cv;
};

std::mutex g_pendingMutex;
std::map<int64_t, ProtectRequest*> g_pendingRequests;

bool EnsureMihomoLoaded() {
    std::lock_guard<std::mutex> lock(g_apiMutex);
    if (g_api.handle != nullptr) {
        return true;
    }

    dlerror();
    g_api.handle = dlopen("libmihomo.so", RTLD_NOW | RTLD_GLOBAL);
    if (!g_api.handle) {
        const char* err = dlerror();
        g_api.loadError = err ? err : "dlopen libmihomo.so failed";
        OH_LOG_ERROR(LOG_APP, "Failed to load libmihomo.so: %{public}s", g_api.loadError.c_str());
        return false;
    }

    g_api.setup = reinterpret_cast<SetupFn>(dlsym(g_api.handle, "Setup"));
    g_api.setProtectCallback = reinterpret_cast<SetProtectCallbackFn>(dlsym(g_api.handle, "SetProtectCallback"));
    g_api.startTun = reinterpret_cast<StartTunFn>(dlsym(g_api.handle, "StartTun"));
    g_api.stop = reinterpret_cast<StopFn>(dlsym(g_api.handle, "Stop"));
    g_api.isRunning = reinterpret_cast<IsRunningFn>(dlsym(g_api.handle, "IsRunning"));
    g_api.setLogLevel = reinterpret_cast<SetLogLevelFn>(dlsym(g_api.handle, "SetLogLevel"));
    g_api.notifyNetworkChange = reinterpret_cast<NotifyNetworkChangeFn>(dlsym(g_api.handle, "NotifyNetworkChange"));
    g_api.getTraffic = reinterpret_cast<GetTrafficFn>(dlsym(g_api.handle, "GetTraffic"));
    g_api.getVersion = reinterpret_cast<GetVersionFn>(dlsym(g_api.handle, "GetVersion"));
    g_api.getLogs = reinterpret_cast<GetLogsFn>(dlsym(g_api.handle, "GetLogs"));
    g_api.clearLogs = reinterpret_cast<ClearLogsFn>(dlsym(g_api.handle, "ClearLogs"));
    g_api.freeString = reinterpret_cast<FreeStringFn>(dlsym(g_api.handle, "FreeString"));

    if (!g_api.setup || !g_api.startTun || !g_api.stop) {
        g_api.loadError = "libmihomo.so missing required symbols";
        OH_LOG_ERROR(LOG_APP, "%{public}s", g_api.loadError.c_str());
        return false;
    }
    OH_LOG_INFO(LOG_APP, "libmihomo.so loaded successfully");
    return true;
}

std::string ConsumeGoString(char* ptr) {
    if (!ptr) {
        return "";
    }
    std::string out(ptr);
    if (g_api.freeString) {
        g_api.freeString(ptr);
    }
    return out;
}

std::string GetStringArg(napi_env env, napi_value val) {
    size_t len = 0;
    napi_get_value_string_utf8(env, val, nullptr, 0, &len);
    std::string s(len, '\0');
    size_t written = 0;
    napi_get_value_string_utf8(env, val, &s[0], len + 1, &written);
    return s;
}

struct TsfnPayload {
    int64_t reqId;
    int fd;
};

void CallJsProtect(napi_env env, napi_value jsCallback, void* /*context*/, void* data) {
    auto* payload = static_cast<TsfnPayload*>(data);
    if (!payload) {
        return;
    }
    int64_t reqId = payload->reqId;
    int fd = payload->fd;
    delete payload;

    if (!env || !jsCallback) {
        std::lock_guard<std::mutex> lock(g_pendingMutex);
        auto it = g_pendingRequests.find(reqId);
        if (it != g_pendingRequests.end()) {
            std::lock_guard<std::mutex> rlock(it->second->mu);
            it->second->done = true;
            it->second->ok = false;
            it->second->cv.notify_one();
        }
        return;
    }

    napi_value argv[2];
    napi_create_int64(env, reqId, &argv[0]);
    napi_create_int32(env, fd, &argv[1]);
    napi_value undefined;
    napi_get_undefined(env, &undefined);
    napi_call_function(env, undefined, jsCallback, 2, argv, nullptr);
}

int NativeProtectBridge(int fd) {
    if (g_processProtected.load()) {
        return 1;
    }

    napi_threadsafe_function tsfn = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_protectMutex);
        tsfn = g_protectTsfn;
    }
    if (!tsfn) {
        return 1;
    }

    ProtectRequest req;
    req.reqId = g_nextReqId.fetch_add(1);
    req.fd = fd;

    {
        std::lock_guard<std::mutex> lock(g_pendingMutex);
        g_pendingRequests[req.reqId] = &req;
    }

    auto* payload = new TsfnPayload{req.reqId, fd};
    napi_status st = napi_call_threadsafe_function(tsfn, payload, napi_tsfn_nonblocking);
    if (st != napi_ok) {
        delete payload;
        std::lock_guard<std::mutex> lock(g_pendingMutex);
        g_pendingRequests.erase(req.reqId);
        return 0;
    }

    bool ok = true;
    {
        std::unique_lock<std::mutex> rlock(req.mu);
        if (req.cv.wait_for(rlock, std::chrono::milliseconds(500), [&req]() { return req.done; })) {
            ok = req.ok;
        } else {
            OH_LOG_WARN(LOG_APP, "protect(%{public}d) timed out", fd);
            ok = true;
        }
    }

    {
        std::lock_guard<std::mutex> lock(g_pendingMutex);
        g_pendingRequests.erase(req.reqId);
    }
    return ok ? 1 : 0;
}

// --- N-API exported methods ---

napi_value NapiIsCoreAvailable(napi_env env, napi_callback_info /*info*/) {
    napi_value res;
    napi_get_boolean(env, EnsureMihomoLoaded(), &res);
    return res;
}

napi_value NapiSetup(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string result;
    if (!EnsureMihomoLoaded()) {
        result = g_api.loadError;
    } else if (argc < 1) {
        result = "missing homeDir";
    } else {
        std::string homeDir = GetStringArg(env, argv[0]);
        result = ConsumeGoString(g_api.setup(const_cast<char*>(homeDir.c_str())));
        if (g_api.setProtectCallback) {
            g_api.setProtectCallback(NativeProtectBridge);
        }
    }

    napi_value out;
    napi_create_string_utf8(env, result.c_str(), result.size(), &out);
    return out;
}

napi_value NapiStartTun(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::string result;
    if (!EnsureMihomoLoaded()) {
        result = g_api.loadError;
    } else if (argc < 2) {
        result = "missing tunFd or configYaml";
    } else {
        int32_t tunFd = -1;
        napi_get_value_int32(env, argv[0], &tunFd);
        std::string yaml = GetStringArg(env, argv[1]);
        OH_LOG_INFO(LOG_APP, "StartTun called: fd=%{public}d, yamlLen=%{public}zu", tunFd, yaml.size());
        result = ConsumeGoString(g_api.startTun(tunFd, const_cast<char*>(yaml.c_str())));
    }

    napi_value out;
    napi_create_string_utf8(env, result.c_str(), result.size(), &out);
    return out;
}

napi_value NapiStop(napi_env env, napi_callback_info /*info*/) {
    if (EnsureMihomoLoaded() && g_api.stop) {
        g_api.stop();
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiIsRunning(napi_env env, napi_callback_info /*info*/) {
    bool running = false;
    if (EnsureMihomoLoaded() && g_api.isRunning) {
        running = g_api.isRunning() != 0;
    }
    napi_value out;
    napi_get_boolean(env, running, &out);
    return out;
}

napi_value NapiSetLogLevel(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1 && EnsureMihomoLoaded() && g_api.setLogLevel) {
        std::string lv = GetStringArg(env, argv[0]);
        g_api.setLogLevel(const_cast<char*>(lv.c_str()));
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiNotifyNetworkChange(napi_env env, napi_callback_info /*info*/) {
    if (EnsureMihomoLoaded() && g_api.notifyNetworkChange) {
        g_api.notifyNetworkChange();
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiGetTraffic(napi_env env, napi_callback_info /*info*/) {
    std::string json = "{\"up\":0,\"down\":0,\"upTotal\":0,\"downTotal\":0}";
    if (EnsureMihomoLoaded() && g_api.getTraffic) {
        json = ConsumeGoString(g_api.getTraffic());
    }
    napi_value out;
    napi_create_string_utf8(env, json.c_str(), json.size(), &out);
    return out;
}

napi_value NapiGetVersion(napi_env env, napi_callback_info /*info*/) {
    std::string ver = "mihomo (unavailable)";
    if (EnsureMihomoLoaded() && g_api.getVersion) {
        ver = ConsumeGoString(g_api.getVersion());
    }
    napi_value out;
    napi_create_string_utf8(env, ver.c_str(), ver.size(), &out);
    return out;
}

napi_value NapiGetLogs(napi_env env, napi_callback_info /*info*/) {
    std::string logs;
    if (EnsureMihomoLoaded() && g_api.getLogs) {
        logs = ConsumeGoString(g_api.getLogs());
    }
    napi_value out;
    napi_create_string_utf8(env, logs.c_str(), logs.size(), &out);
    return out;
}

napi_value NapiClearLogs(napi_env env, napi_callback_info /*info*/) {
    if (EnsureMihomoLoaded() && g_api.clearLogs) {
        g_api.clearLogs();
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiSetProcessProtected(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 1) {
        bool v = false;
        napi_get_value_bool(env, argv[0], &v);
        g_processProtected.store(v);
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiRegisterProtectCallback(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value argv[1];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);

    std::lock_guard<std::mutex> lock(g_protectMutex);
    if (g_protectTsfn != nullptr) {
        napi_release_threadsafe_function(g_protectTsfn, napi_tsfn_abort);
        g_protectTsfn = nullptr;
    }

    if (argc >= 1) {
        napi_valuetype type;
        napi_typeof(env, argv[0], &type);
        if (type == napi_function) {
            napi_value name;
            napi_create_string_utf8(env, "TizLinkProtectSocket", NAPI_AUTO_LENGTH, &name);
            napi_create_threadsafe_function(
                env, argv[0], nullptr, name, 0, 1, nullptr, nullptr, nullptr, CallJsProtect, &g_protectTsfn);
            if (EnsureMihomoLoaded() && g_api.setProtectCallback) {
                g_api.setProtectCallback(NativeProtectBridge);
            }
        }
    }

    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

napi_value NapiResolveProtect(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value argv[2];
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    if (argc >= 2) {
        int64_t reqId = 0;
        bool ok = false;
        napi_get_value_int64(env, argv[0], &reqId);
        napi_get_value_bool(env, argv[1], &ok);

        std::lock_guard<std::mutex> lock(g_pendingMutex);
        auto it = g_pendingRequests.find(reqId);
        if (it != g_pendingRequests.end()) {
            std::lock_guard<std::mutex> rlock(it->second->mu);
            it->second->done = true;
            it->second->ok = ok;
            it->second->cv.notify_one();
        }
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"isCoreAvailable", nullptr, NapiIsCoreAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setup", nullptr, NapiSetup, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"startTun", nullptr, NapiStartTun, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stop", nullptr, NapiStop, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"isRunning", nullptr, NapiIsRunning, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setLogLevel", nullptr, NapiSetLogLevel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"notifyNetworkChange", nullptr, NapiNotifyNetworkChange, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getTraffic", nullptr, NapiGetTraffic, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getVersion", nullptr, NapiGetVersion, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getLogs", nullptr, NapiGetLogs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"clearLogs", nullptr, NapiClearLogs, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"setProcessProtected", nullptr, NapiSetProcessProtected, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"registerProtectCallback", nullptr, NapiRegisterProtectCallback, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"resolveProtect", nullptr, NapiResolveProtect, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module tizlinkNativeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "tizlink_native",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterTizlinkNativeModule(void) {
    napi_module_register(&tizlinkNativeModule);
}
