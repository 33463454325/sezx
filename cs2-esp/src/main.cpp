// ============================================================================
// CS2 ESP — Main entry point
// ============================================================================
// External overlay ESP for Counter-Strike 2.
// Reads game memory via ReadProcessMemory, draws with D3D11 + ImGui overlay.
//
// Hotkeys:
//   INSERT  — toggle settings menu
//   END     — exit
//
// IMPORTANT: Offsets in offsets.h must be populated for your game build.
//            Run cs2-dumper and paste the values before compiling.
// ============================================================================

#include "process.h"
#include "entity.h"
#include "overlay.h"
#include "esp_renderer.h"
#include "offsets.h"
#include <cstdio>
#include <thread>
#include <chrono>

int main() {
    // --- Banner ---
    printf("[CS2 ESP] Starting...\n");
    printf("[CS2 ESP] Build config: %s\n", offsets::build_id);

    // Check if any critical offsets are populated.
    if (!offsets::is_set(offsets::dwEntityList) ||
        !offsets::is_set(offsets::dwViewMatrix) ||
        !offsets::is_set(offsets::dwLocalPlayerPawn)) {
        printf("[!] CRITICAL: Core offsets are not set (dwEntityList, dwViewMatrix, dwLocalPlayerPawn).\n");
        printf("[!] Run cs2-dumper for your build and populate offsets.h before using.\n");
        printf("[!] Continuing anyway — ESP will not draw until offsets are filled.\n\n");
    }

    // --- Attach to CS2 ---
    Process proc;
    printf("[CS2 ESP] Waiting for cs2.exe...\n");
    while (!proc.attach(L"cs2.exe")) {
        if (GetAsyncKeyState(VK_END) & 0x8000) {
            printf("[CS2 ESP] Exit requested.\n");
            return 0;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
    }
    printf("[CS2 ESP] Attached to cs2.exe (PID %lu)\n", proc.pid());

    // --- Find client.dll ---
    auto client_mod = proc.get_module(L"client.dll");
    if (!client_mod) {
        printf("[!] Could not find client.dll — is CS2 fully loaded?\n");
        return 1;
    }
    printf("[CS2 ESP] client.dll base: 0x%llX  size: 0x%X\n",
        static_cast<unsigned long long>(client_mod->base), client_mod->size);

    EntityReader reader(proc);
    reader.set_client_base(client_mod->base);

    // --- Init overlay ---
    Overlay overlay;
    if (!overlay.init()) {
        printf("[!] Failed to initialize overlay.\n");
        return 1;
    }
    printf("[CS2 ESP] Overlay initialized (%dx%d)\n", overlay.width(), overlay.height());
    printf("[CS2 ESP] INSERT = menu | END = exit\n\n");

    // --- Main loop ---
    esp::Settings settings;
    bool show_menu = false;
    bool insert_held = false;

    while (true) {
        // Exit hotkey.
        if (GetAsyncKeyState(VK_END) & 0x8000)
            break;

        // Process died.
        if (!proc.is_alive()) {
            printf("[CS2 ESP] cs2.exe exited.\n");
            break;
        }

        // Toggle menu on INSERT press (edge-triggered).
        bool insert_down = (GetAsyncKeyState(VK_INSERT) & 0x8000) != 0;
        if (insert_down && !insert_held) {
            show_menu = !show_menu;

            // When menu is open, make overlay accept input.
            LONG_PTR ex_style = GetWindowLongPtrW(overlay.hwnd(), GWL_EXSTYLE);
            if (show_menu)
                SetWindowLongPtrW(overlay.hwnd(), GWL_EXSTYLE, ex_style & ~WS_EX_TRANSPARENT);
            else
                SetWindowLongPtrW(overlay.hwnd(), GWL_EXSTYLE, ex_style | WS_EX_TRANSPARENT);
        }
        insert_held = insert_down;

        // Begin overlay frame.
        if (!overlay.begin_frame()) {
            printf("[CS2 ESP] Game window lost.\n");
            break;
        }

        if (settings.enable_esp) {
            // Read view matrix.
            ViewMatrix vm{};
            reader.read_view_matrix(vm);

            // Read local player info.
            Vec3 local_pos{};
            reader.read_local_player_pos(local_pos);
            int local_team = reader.read_local_team();

            // Read entities and draw.
            auto players = reader.read_players(local_pos,
                settings.team_check ? local_team : -1);

            ImDrawList* dl = ImGui::GetBackgroundDrawList();
            for (const auto& p : players) {
                esp::draw_player(dl, p, vm, settings,
                    overlay.width(), overlay.height());
            }
        }

        // Settings menu.
        esp::draw_menu(settings, show_menu);

        overlay.end_frame();
    }

    printf("[CS2 ESP] Shutting down.\n");
    return 0;
}
