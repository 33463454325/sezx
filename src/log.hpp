#pragma once
#include <android/log.h>

#define VK_TAG "vektor"
#define VK_LOGI(...) __android_log_print(ANDROID_LOG_INFO,  VK_TAG, __VA_ARGS__)
#define VK_LOGW(...) __android_log_print(ANDROID_LOG_WARN,  VK_TAG, __VA_ARGS__)
#define VK_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, VK_TAG, __VA_ARGS__)
