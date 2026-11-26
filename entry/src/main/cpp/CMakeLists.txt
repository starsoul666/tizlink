cmake_minimum_required(VERSION 3.5.0)
project(tizlink_native)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

add_library(tizlink_native SHARED napi_init.cpp)

target_link_libraries(tizlink_native PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    dl
)
