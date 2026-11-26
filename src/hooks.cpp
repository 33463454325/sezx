#include "hooks.hpp"
#include "log.hpp"
#include <sys/mman.h>
#include <unistd.h>
#include <cstdint>
#include <cstring>

// Minimal ARM64 inline hook — no Dobby dependency.
// Overwrites first 16 bytes of target with:
//   ldr x17, [pc, #8]   ; 0x58000051
//   br  x17             ; 0xd61f0220
//   <addr>              ; 8 bytes absolute
// Saves original 16 bytes + emits a trampoline (orig_bytes + jump back) on
// an anonymous RX page so callers can invoke the real function via *orig.

namespace hk {

static constexpr uint32_t LDR_X17_PC8 = 0x58000051u;
static constexpr uint32_t BR_X17      = 0xD61F0220u;

static bool unprotect_page(void* p, size_t n) {
    long ps = sysconf(_SC_PAGESIZE);
    auto a = reinterpret_cast<uintptr_t>(p) & ~(ps - 1);
    auto e = (reinterpret_cast<uintptr_t>(p) + n + ps - 1) & ~(ps - 1);
    return mprotect(reinterpret_cast<void*>(a), e - a,
                    PROT_READ | PROT_WRITE | PROT_EXEC) == 0;
}

static void flush_icache(void* p, size_t n) {
    __builtin___clear_cache(reinterpret_cast<char*>(p),
                            reinterpret_cast<char*>(p) + n);
}

bool install(void* target, void* replace, void** orig) {
    if (!target || !replace) return false;

    // Allocate an executable trampoline: first 16 bytes of target,
    // then absolute jump back to target+16.
    size_t tramp_sz = 16 + 16;
    void* tramp = mmap(nullptr, tramp_sz,
                       PROT_READ | PROT_WRITE | PROT_EXEC,
                       MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (tramp == MAP_FAILED) {
        VK_LOGE("hook: mmap trampoline failed");
        return false;
    }
    std::memcpy(tramp, target, 16);
    uint32_t* tp = reinterpret_cast<uint32_t*>(
        reinterpret_cast<uint8_t*>(tramp) + 16);
    tp[0] = LDR_X17_PC8;
    tp[1] = BR_X17;
    uintptr_t after = reinterpret_cast<uintptr_t>(target) + 16;
    std::memcpy(tp + 2, &after, sizeof(after));
    flush_icache(tramp, tramp_sz);
    if (orig) *orig = tramp;

    // Patch target with jump to replace.
    if (!unprotect_page(target, 16)) {
        VK_LOGE("hook: mprotect target failed");
        return false;
    }
    uint32_t* dst = reinterpret_cast<uint32_t*>(target);
    dst[0] = LDR_X17_PC8;
    dst[1] = BR_X17;
    uintptr_t rep = reinterpret_cast<uintptr_t>(replace);
    std::memcpy(dst + 2, &rep, sizeof(rep));
    flush_icache(target, 16);

    VK_LOGI("hook: installed %p -> %p (tramp=%p)", target, replace, tramp);
    return true;
}

}  // namespace hk
