#include "log.hpp"
#include <pthread.h>
#include <unistd.h>

void install_gles_hook();

static void* boot(void*) {
    VK_LOGI("boot: VEKTOR waking up (pid=%d)", getpid());
    // Give the game a few seconds to initialize EGL before we install hooks.
    sleep(2);
    install_gles_hook();
    VK_LOGI("boot: hooks installed, menu waiting for first frame");
    return nullptr;
}

__attribute__((constructor))
static void on_load() {
    pthread_t t;
    pthread_create(&t, nullptr, boot, nullptr);
    pthread_detach(t);
}

extern "C" __attribute__((visibility("default")))
int JNI_OnLoad(void* /*vm*/, void* /*reserved*/) {
    VK_LOGI("JNI_OnLoad called");
    return 0x00010006;  // JNI_VERSION_1_6
}
