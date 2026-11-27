#pragma once
// ============================================================================
// CS2 ESP — Drawing routines (box, health bar, name, snapline, skeleton)
// ============================================================================
// All drawing goes through ImGui's draw list.
// Colors: enemy = red family, spotted = yellow, flashed = white.
// ============================================================================

#include "entity.h"
#include "math.h"
#include "imgui.h"
#include <cstdio>

namespace esp {

// ESP feature toggles (runtime-configurable via ImGui menu).
struct Settings {
    bool enable_esp      = true;
    bool draw_box        = true;
    bool draw_health_bar = true;
    bool draw_name       = true;
    bool draw_distance   = true;
    bool draw_snapline   = false;
    bool draw_skeleton   = false;
    bool draw_head_dot   = true;
    bool draw_weapon     = false;
    bool draw_flags      = true;   // scoped, flashed, helmet, armor
    bool team_check      = true;   // skip teammates
    float max_distance   = 0.f;    // 0 = unlimited

    // Colors (RGBA).
    ImU32 color_enemy    = IM_COL32(255, 50, 50, 255);
    ImU32 color_visible  = IM_COL32(255, 255, 50, 255);  // spotted
    ImU32 color_health_high = IM_COL32(50, 255, 50, 255);
    ImU32 color_health_low  = IM_COL32(255, 50, 50, 255);
    ImU32 color_name     = IM_COL32(255, 255, 255, 255);
    ImU32 color_snapline = IM_COL32(255, 255, 255, 100);
    ImU32 color_skeleton = IM_COL32(255, 255, 255, 200);
    ImU32 color_head     = IM_COL32(255, 255, 50, 255);
};

// Source 2 CS2 bone indices for a simplified skeleton.
// These are model-dependent — verify on your build in ReClass.
namespace bones {
    inline constexpr int HEAD       = 6;
    inline constexpr int NECK       = 5;
    inline constexpr int SPINE_1    = 4;
    inline constexpr int SPINE_2    = 2;
    inline constexpr int PELVIS     = 0;
    inline constexpr int L_SHOULDER = 8;
    inline constexpr int L_ELBOW    = 9;
    inline constexpr int L_HAND     = 10;
    inline constexpr int R_SHOULDER = 13;
    inline constexpr int R_ELBOW    = 14;
    inline constexpr int R_HAND     = 15;
    inline constexpr int L_HIP      = 22;
    inline constexpr int L_KNEE     = 23;
    inline constexpr int L_FOOT     = 24;
    inline constexpr int R_HIP      = 25;
    inline constexpr int R_KNEE     = 26;
    inline constexpr int R_FOOT     = 27;
}

struct BonePair { int from, to; };

inline constexpr BonePair SKELETON_PAIRS[] = {
    {bones::HEAD,       bones::NECK},
    {bones::NECK,       bones::SPINE_1},
    {bones::SPINE_1,    bones::SPINE_2},
    {bones::SPINE_2,    bones::PELVIS},
    {bones::NECK,       bones::L_SHOULDER},
    {bones::L_SHOULDER, bones::L_ELBOW},
    {bones::L_ELBOW,    bones::L_HAND},
    {bones::NECK,       bones::R_SHOULDER},
    {bones::R_SHOULDER, bones::R_ELBOW},
    {bones::R_ELBOW,    bones::R_HAND},
    {bones::PELVIS,     bones::L_HIP},
    {bones::L_HIP,      bones::L_KNEE},
    {bones::L_KNEE,     bones::L_FOOT},
    {bones::PELVIS,     bones::R_HIP},
    {bones::R_HIP,      bones::R_KNEE},
    {bones::R_KNEE,     bones::R_FOOT},
};

inline void draw_player(
    ImDrawList* dl,
    const PlayerData& p,
    const ViewMatrix& vm,
    const Settings& s,
    int screen_w,
    int screen_h)
{
    if (!p.valid_position) return;
    if (s.max_distance > 0.f && p.distance > s.max_distance) return;

    // Project feet and head to screen.
    auto feet_screen = world_to_screen(p.position, vm, screen_w, screen_h);
    auto head_screen = world_to_screen(p.head_position, vm, screen_w, screen_h);

    if (!feet_screen || !head_screen) return;

    Vec2 ft = *feet_screen;
    Vec2 hd = *head_screen;

    float box_h = ft.y - hd.y;
    if (box_h < 2.f) return; // Too small to draw.
    float box_w = box_h * 0.5f;

    float left   = hd.x - box_w * 0.5f;
    float top    = hd.y;
    float right  = hd.x + box_w * 0.5f;
    float bottom = ft.y;

    ImU32 main_color = p.is_spotted ? s.color_visible : s.color_enemy;

    // --- Box ESP ---
    if (s.draw_box) {
        // Outline for visibility.
        dl->AddRect(ImVec2(left - 1, top - 1), ImVec2(right + 1, bottom + 1), IM_COL32(0, 0, 0, 180));
        dl->AddRect(ImVec2(left, top), ImVec2(right, bottom), main_color, 0.f, 0, 1.5f);
    }

    // --- Health bar (left side) ---
    if (s.draw_health_bar && p.valid_health) {
        float bar_w  = 3.f;
        float bar_x  = left - bar_w - 3.f;
        float health_frac = static_cast<float>(p.health) / 100.f;
        if (health_frac > 1.f) health_frac = 1.f;

        float bar_top    = top;
        float bar_bottom = bottom;
        float bar_filled = bar_bottom - (bar_bottom - bar_top) * health_frac;

        // Lerp green→red based on health.
        int r = static_cast<int>((1.f - health_frac) * 255.f);
        int g = static_cast<int>(health_frac * 255.f);
        ImU32 hp_color = IM_COL32(r, g, 0, 255);

        dl->AddRectFilled(ImVec2(bar_x, bar_top), ImVec2(bar_x + bar_w, bar_bottom), IM_COL32(0, 0, 0, 150));
        dl->AddRectFilled(ImVec2(bar_x, bar_filled), ImVec2(bar_x + bar_w, bar_bottom), hp_color);

        // Health number if below 100.
        if (p.health < 100) {
            char hp_text[8];
            snprintf(hp_text, sizeof(hp_text), "%d", p.health);
            dl->AddText(ImVec2(bar_x - 2, bar_filled - 7), s.color_name, hp_text);
        }
    }

    // --- Name ---
    if (s.draw_name && p.valid_name) {
        ImVec2 text_size = ImGui::CalcTextSize(p.name.c_str());
        float text_x = hd.x - text_size.x * 0.5f;
        float text_y = top - text_size.y - 2.f;
        dl->AddText(ImVec2(text_x + 1, text_y + 1), IM_COL32(0, 0, 0, 200), p.name.c_str());
        dl->AddText(ImVec2(text_x, text_y), s.color_name, p.name.c_str());
    }

    // --- Distance ---
    if (s.draw_distance) {
        char dist_text[16];
        snprintf(dist_text, sizeof(dist_text), "%.0fm", p.distance / 100.f);
        ImVec2 text_size = ImGui::CalcTextSize(dist_text);
        float text_x = hd.x - text_size.x * 0.5f;
        dl->AddText(ImVec2(text_x + 1, bottom + 2 + 1), IM_COL32(0, 0, 0, 200), dist_text);
        dl->AddText(ImVec2(text_x, bottom + 2), s.color_name, dist_text);
    }

    // --- Snapline (bottom center → player feet) ---
    if (s.draw_snapline) {
        dl->AddLine(
            ImVec2(screen_w * 0.5f, static_cast<float>(screen_h)),
            ImVec2(ft.x, ft.y),
            s.color_snapline, 1.f
        );
    }

    // --- Head dot ---
    if (s.draw_head_dot) {
        float radius = box_h * 0.06f;
        if (radius < 2.f) radius = 2.f;
        // Project actual head bone or approximate.
        dl->AddCircleFilled(ImVec2(hd.x, hd.y + radius * 1.5f), radius, s.color_head);
    }

    // --- Flags (right side) ---
    if (s.draw_flags) {
        float flag_y = top;
        float flag_x = right + 4.f;
        auto add_flag = [&](const char* text) {
            dl->AddText(ImVec2(flag_x + 1, flag_y + 1), IM_COL32(0, 0, 0, 200), text);
            dl->AddText(ImVec2(flag_x, flag_y), s.color_name, text);
            flag_y += ImGui::GetTextLineHeight();
        };
        if (p.has_helmet && p.armor > 0) add_flag("HK");
        else if (p.armor > 0)            add_flag("K");
        if (p.is_scoped)                 add_flag("ZOOM");
        if (p.flash_duration > 0.f)      add_flag("FLASH");
    }

    // --- Skeleton ---
    if (s.draw_skeleton && p.has_bones) {
        for (const auto& pair : SKELETON_PAIRS) {
            if (pair.from >= static_cast<int>(p.bones.size()) ||
                pair.to   >= static_cast<int>(p.bones.size()))
                continue;

            auto s1 = world_to_screen(p.bones[pair.from].position, vm, screen_w, screen_h);
            auto s2 = world_to_screen(p.bones[pair.to].position, vm, screen_w, screen_h);
            if (s1 && s2) {
                dl->AddLine(ImVec2(s1->x, s1->y), ImVec2(s2->x, s2->y), s.color_skeleton, 1.5f);
            }
        }
    }
}

// Draw the settings menu (toggled by INSERT key).
inline void draw_menu(Settings& s, bool& show_menu) {
    if (!show_menu) return;

    ImGui::SetNextWindowSize(ImVec2(280, 350), ImGuiCond_FirstUseEver);
    ImGui::Begin("ESP Settings", &show_menu,
        ImGuiWindowFlags_NoCollapse | ImGuiWindowFlags_AlwaysAutoResize);

    ImGui::Checkbox("Enable ESP",      &s.enable_esp);
    ImGui::Separator();
    ImGui::Checkbox("Box",             &s.draw_box);
    ImGui::Checkbox("Health Bar",      &s.draw_health_bar);
    ImGui::Checkbox("Name",            &s.draw_name);
    ImGui::Checkbox("Distance",        &s.draw_distance);
    ImGui::Checkbox("Snaplines",       &s.draw_snapline);
    ImGui::Checkbox("Skeleton",        &s.draw_skeleton);
    ImGui::Checkbox("Head Dot",        &s.draw_head_dot);
    ImGui::Checkbox("Flags",           &s.draw_flags);
    ImGui::Separator();
    ImGui::Checkbox("Team Check",      &s.team_check);
    ImGui::SliderFloat("Max Dist", &s.max_distance, 0.f, 10000.f, "%.0f (0=inf)");

    ImGui::End();
}

} // namespace esp
