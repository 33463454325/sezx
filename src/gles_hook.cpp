#include "hooks.hpp"
#include "menu.hpp"
#include "log.hpp"

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <dlfcn.h>
#include <imgui.h>

using swap_t = EGLBoolean (*)(EGLDisplay, EGLSurface);
static swap_t real_swap = nullptr;

static EGLBoolean my_swap(EGLDisplay d, EGLSurface s) {
    EGLint w = 0, h = 0;
    eglQuerySurface(d, s, EGL_WIDTH,  &w);
    eglQuerySurface(d, s, EGL_HEIGHT, &h);
    if (w > 0 && h > 0) {
        ui::init(w, h);
        ImGuiIO& io = ImGui::GetIO();
        io.DisplaySize = ImVec2((float)w, (float)h);
        io.DeltaTime   = 1.0f / 60.0f;
        ui::frame();
    }
    return real_swap(d, s);
}

void install_gles_hook() {
    void* lib = dlopen("libEGL.so", RTLD_NOW);
    if (!lib) { VK_LOGE("libEGL.so not loaded"); return; }
    void* fn = dlsym(lib, "eglSwapBuffers");
    if (!fn) { VK_LOGE("eglSwapBuffers not found"); return; }
    if (hk::install(fn, reinterpret_cast<void*>(&my_swap),
                    reinterpret_cast<void**>(&real_swap))) {
        VK_LOGI("gles: eglSwapBuffers hooked");
    }
}
