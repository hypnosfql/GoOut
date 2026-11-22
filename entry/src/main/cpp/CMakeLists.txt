cmake_minimum_required(VERSION 3.16)
project(gooutcore C CXX ASM)

set(CMAKE_CXX_STANDARD 17)

# --- prebuilt Go bridge (libgoout.so) ---
set(GOOUT_PREBUILT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/goout/prebuilt/${OHOS_ARCH})

add_library(goout SHARED IMPORTED)
set_target_properties(goout PROPERTIES IMPORTED_LOCATION ${GOOUT_PREBUILT}/libgoout.so)

add_library(golog SHARED IMPORTED)
set_target_properties(golog PROPERTIES IMPORTED_LOCATION ${GOOUT_PREBUILT}/liblog.so)

# ============================================================
# hev-socks5-tunnel（tun ⇄ socks5 桥，C 实现，低开销）
# ============================================================
set(HEV_ROOT ${CMAKE_CURRENT_SOURCE_DIR}/third_party/hev)

# --- third-part/yaml ---
file(GLOB_RECURSE YAML_SRCS ${HEV_ROOT}/third-part/yaml/src/*.c)
add_library(hev_yaml STATIC ${YAML_SRCS})
target_include_directories(hev_yaml PUBLIC ${HEV_ROOT}/third-part/yaml/include
                                    PRIVATE ${HEV_ROOT}/third-part/yaml/src)
target_compile_definitions(hev_yaml PRIVATE
    YAML_VERSION_MAJOR=0
    YAML_VERSION_MINOR=2
    YAML_VERSION_PATCH=5
    YAML_VERSION_STRING="0.2.5")

# --- third-part/lwip ---
file(GLOB_RECURSE LWIP_SRCS ${HEV_ROOT}/third-part/lwip/src/*.c)
add_library(hev_lwip STATIC ${LWIP_SRCS})
target_include_directories(hev_lwip PUBLIC
    ${HEV_ROOT}/third-part/lwip/src/include
    ${HEV_ROOT}/third-part/lwip/src/ports/include)
target_compile_definitions(hev_lwip PRIVATE FD_SET_DEFINED SOCKLEN_T_DEFINED)
target_compile_options(hev_lwip PRIVATE -fno-stack-clash-protection)

# --- third-part/hev-task-system ---
file(GLOB_RECURSE HTS_SRCS ${HEV_ROOT}/third-part/hev-task-system/src/*.c
                           ${HEV_ROOT}/third-part/hev-task-system/src/*.S)
# 顶层 .S 已按宏 include 对应 arch 实现，排除 arch 目录防止重复/误编
list(FILTER HTS_SRCS EXCLUDE REGEX ".*/arch/.*")
add_library(hev_task_system STATIC ${HTS_SRCS})
target_include_directories(hev_task_system PUBLIC ${HEV_ROOT}/third-part/hev-task-system/include
                                          PRIVATE ${HEV_ROOT}/third-part/hev-task-system/src)
target_compile_definitions(hev_task_system PRIVATE
    ENABLE_STACK_OVERFLOW_DETECTION=1
    CONFIG_STACK_OVERFLOW_DETECTION=1
    CONFIG_STACK_BACKEND=STACK_MMAP
    CONFIG_MEMALLOC_SLICE_ALIGN=16
    CONFIG_MEMALLOC_SLICE_MAX_SIZE=4096
    CONFIG_MEMALLOC_SLICE_MAX_COUNT=1000
    CONFIG_SCHED_CLOCK=CLOCK_REALTIME)
target_compile_options(hev_task_system PRIVATE -fno-stack-clash-protection -fvisibility=hidden)

# --- hev 本体（ENABLE_LIBRARY：只出 API，无 main） ---
file(GLOB_RECURSE HEV_SRCS ${HEV_ROOT}/src/*.c)
list(FILTER HEV_SRCS EXCLUDE REGEX ".*hev-jni\\.c$")
add_library(hev STATIC ${HEV_SRCS})
target_include_directories(hev PUBLIC
    ${HEV_ROOT}/src
    ${HEV_ROOT}/src/misc
    ${HEV_ROOT}/src/core/include
    ${HEV_ROOT}/third-part/yaml/include
    ${HEV_ROOT}/third-part/lwip/src/include
    ${HEV_ROOT}/third-part/lwip/src/ports/include
    ${HEV_ROOT}/third-part/hev-task-system/include)
target_compile_definitions(hev PRIVATE FD_SET_DEFINED SOCKLEN_T_DEFINED ENABLE_LIBRARY)
target_compile_options(hev PRIVATE -fno-stack-clash-protection)
target_link_libraries(hev PUBLIC hev_yaml hev_lwip hev_task_system)

# ============================================================
# NAPI 模块
# ============================================================
add_library(gooutcore SHARED napi_init.cpp hev_bridge.c)

target_include_directories(gooutcore PRIVATE ${GOOUT_PREBUILT} ${HEV_ROOT}/src)

target_link_libraries(gooutcore PUBLIC goout golog hev libace_napi.z.so libhilog_ndk.z.so)
