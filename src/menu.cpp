#include "menu.hpp"
#include "log.hpp"

#include <imgui.h>
#include <backends/imgui_impl_opengl3.h>

namespace ui {

static bool g_inited = false;
static bool g_show   = true;

static void style_dark_red() {
    auto& s = ImGui::GetStyle();
    s.WindowRounding = 12; s.FrameRounding = 8; s.GrabRounding = 8;
    s.ChildRounding  = 10; s.PopupRounding = 10; s.TabRounding = 8;
    s.WindowPadding  = ImVec2(16, 16);
    s.FramePadding   = ImVec2(10, 7);
    s.ItemSpacing    = ImVec2(12, 10);

    auto& c = s.Colors;
    c[ImGuiCol_WindowBg]        = ImVec4(0.070f, 0.023f, 0.030f, 0.96f);
    c[ImGuiCol_ChildBg]         = ImVec4(0.100f, 0.035f, 0.050f, 1.00f);
    c[ImGuiCol_FrameBg]         = ImVec4(0.150f, 0.045f, 0.070f, 1.00f);
    c[ImGuiCol_FrameBgHovered]  = ImVec4(0.220f, 0.065f, 0.100f, 1.00f);
    c[ImGuiCol_TitleBg]         = ImVec4(0.180f, 0.045f, 0.070f, 1.00f);
    c[ImGuiCol_TitleBgActive]   = ImVec4(0.420f, 0.070f, 0.110f, 1.00f);
    c[ImGuiCol_Button]          = ImVec4(0.260f, 0.070f, 0.100f, 1.00f);
    c[ImGuiCol_ButtonHovered]   = ImVec4(0.520f, 0.100f, 0.150f, 1.00f);
    c[ImGuiCol_CheckMark]       = ImVec4(1.000f, 0.280f, 0.360f, 1.00f);
    c[ImGuiCol_SliderGrab]      = ImVec4(0.980f, 0.230f, 0.300f, 1.00f);
    c[ImGuiCol_SliderGrabActive]= ImVec4(1.000f, 0.420f, 0.480f, 1.00f);
    c[ImGuiCol_Tab]             = ImVec4(0.170f, 0.045f, 0.070f, 1.00f);
    c[ImGuiCol_TabHovered]      = ImVec4(0.620f, 0.130f, 0.180f, 1.00f);
    c[ImGuiCol_TabActive]       = ImVec4(0.760f, 0.150f, 0.200f, 1.00f);
    c[ImGuiCol_Text]            = ImVec4(0.96f, 0.95f, 0.95f, 1.00f);
    c[ImGuiCol_TextDisabled]    = ImVec4(0.65f, 0.52f, 0.55f, 1.00f);
    c[ImGuiCol_Separator]       = ImVec4(0.30f, 0.06f, 0.09f, 1.00f);
}

void init(int w, int h) {
    if (g_inited) return;
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.DisplaySize = ImVec2((float)w, (float)h);
    io.FontGlobalScale = 1.3f;
    style_dark_red();
    ImGui_ImplOpenGL3_Init("#version 300 es");
    g_inited = true;
    VK_LOGI("ui: inited %dx%d", w, h);
}

struct Cfg {
    bool aim = false;
    bool esp = true;
    bool wall = false;
    bool trigger = false;
    bool rapid = false;
    bool recoil = true;
    bool bhop = false;
    bool no_fall = true;
    float smooth = 0.25f;
    float fov = 180.0f;
    int bone = 0;
    bool skins = true;
    float wear = 0.07f;
    bool stattrak = true;
    bool guard_proc = true;
    bool guard_ptrace = true;
    bool guard_fairplay = true;
    bool guard_threads = true;
    char search[64] = "";
};
static Cfg g_cfg;

static void tab_aim() {
    ImGui::Checkbox("Аимбот",         &g_cfg.aim);
    ImGui::Checkbox("Триггер-бот",    &g_cfg.trigger);
    ImGui::SliderFloat("FOV",         &g_cfg.fov,    20.0f, 600.0f, "%.0f");
    ImGui::SliderFloat("Плавность",   &g_cfg.smooth,  0.02f, 1.0f, "%.2f");
    const char* bones[] = {"голова","корпус","таз"};
    ImGui::Combo("Кость", &g_cfg.bone, bones, 3);
    ImGui::TextDisabled("Оффсеты не дампнуты — работает только меню");
}
static void tab_esp() {
    ImGui::Checkbox("ESP коробки",   &g_cfg.esp);
    ImGui::Checkbox("Chams по стенам", &g_cfg.wall);
    ImGui::TextDisabled("Нужен рантайм-дамп классов из libunity.so");
}
static void tab_weapon() {
    ImGui::Checkbox("Без отдачи",   &g_cfg.recoil);
    ImGui::Checkbox("Рапид",        &g_cfg.rapid);
}
static void tab_move() {
    ImGui::Checkbox("Банни-хоп",    &g_cfg.bhop);
    ImGui::Checkbox("No fall",      &g_cfg.no_fall);
}
static void tab_skins() {
    ImGui::Checkbox("Смена скинов", &g_cfg.skins);
    ImGui::InputTextWithHint("##s", "Поиск скина, оружия…", g_cfg.search, sizeof(g_cfg.search));
    ImGui::SliderFloat("Износ", &g_cfg.wear, 0.0f, 1.0f, "%.3f");
    ImGui::Checkbox("StatTrak", &g_cfg.stattrak);
    const char* tier =
        g_cfg.wear <= 0.07f ? "Factory New"  :
        g_cfg.wear <= 0.15f ? "Minimal Wear" :
        g_cfg.wear <= 0.37f ? "Field-Tested" :
        g_cfg.wear <= 0.45f ? "Well-Worn"    : "Battle-Scarred";
    ImGui::Text("Состояние: %s", tier);
}
static void tab_guard() {
    ImGui::Checkbox("Скрытие в /proc",       &g_cfg.guard_proc);
    ImGui::Checkbox("Блок ptrace",           &g_cfg.guard_ptrace);
    ImGui::Checkbox("Нейтрализация Fairplay",&g_cfg.guard_fairplay);
    ImGui::Checkbox("Заморозка потоков",     &g_cfg.guard_threads);
    ImGui::TextDisabled("Слои Guard + Humanize активны");
}

void frame() {
    if (!g_inited) return;
    ImGui_ImplOpenGL3_NewFrame();
    ImGui::NewFrame();
    if (g_show) {
        ImGui::SetNextWindowSize(ImVec2(760, 540), ImGuiCond_FirstUseEver);
        ImGui::Begin("VEKTOR  ·  Standoff 2");
        if (ImGui::BeginTabBar("tabs")) {
            if (ImGui::BeginTabItem("Прицел"))   { tab_aim();    ImGui::EndTabItem(); }
            if (ImGui::BeginTabItem("ESP"))      { tab_esp();    ImGui::EndTabItem(); }
            if (ImGui::BeginTabItem("Оружие"))   { tab_weapon(); ImGui::EndTabItem(); }
            if (ImGui::BeginTabItem("Движение")) { tab_move();   ImGui::EndTabItem(); }
            if (ImGui::BeginTabItem("Скины"))    { tab_skins();  ImGui::EndTabItem(); }
            if (ImGui::BeginTabItem("Защита"))   { tab_guard();  ImGui::EndTabItem(); }
            ImGui::EndTabBar();
        }
        ImGui::End();
    }
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

}  // namespace ui
