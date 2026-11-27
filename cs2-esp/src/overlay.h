#pragma once
// ============================================================================
// CS2 ESP — D3D11 + ImGui transparent overlay
// ============================================================================
// Creates a transparent, click-through, topmost window that tracks the game
// window's position and size. Renders with D3D11 and ImGui.
// RAII: device, swapchain, render target and window are released on destruction.
// Handles resize and device loss gracefully.
// ============================================================================

#include <Windows.h>
#include <d3d11.h>
#include <dxgi.h>
#include <wrl/client.h>
#include <string>

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "dxgi.lib")

#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"

// Forward-declare the ImGui WndProc handler.
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND, UINT, WPARAM, LPARAM);

class Overlay {
public:
    Overlay() = default;
    ~Overlay() { shutdown(); }

    Overlay(const Overlay&) = delete;
    Overlay& operator=(const Overlay&) = delete;

    struct Config {
        std::wstring window_title = L"CS2 ESP Overlay";
        // If empty, tracks the game window automatically.
        std::wstring game_window_class = L"SDL_app";
        std::wstring game_window_title = L"Counter-Strike 2";
    };

    bool init(const Config& cfg = {}) {
        cfg_ = cfg;

        // Register window class.
        WNDCLASSEXW wc{};
        wc.cbSize        = sizeof(wc);
        wc.style         = CS_HREDRAW | CS_VREDRAW;
        wc.lpfnWndProc   = wnd_proc;
        wc.hInstance      = GetModuleHandleW(nullptr);
        wc.lpszClassName  = L"CS2ESPOverlayClass";
        if (!RegisterClassExW(&wc)) return false;

        // Create layered, transparent, topmost, tool window.
        hwnd_ = CreateWindowExW(
            WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_LAYERED | WS_EX_TOOLWINDOW,
            wc.lpszClassName,
            cfg_.window_title.c_str(),
            WS_POPUP,
            0, 0, 1920, 1080,
            nullptr, nullptr, wc.hInstance, nullptr
        );
        if (!hwnd_) return false;

        // Set full transparency on the window.
        SetLayeredWindowAttributes(hwnd_, RGB(0, 0, 0), 0, LWA_COLORKEY);
        ShowWindow(hwnd_, SW_SHOWDEFAULT);
        UpdateWindow(hwnd_);

        if (!create_device()) {
            shutdown();
            return false;
        }

        // ImGui setup.
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();

        ImGuiIO& io = ImGui::GetIO();
        io.IniFilename = nullptr; // No .ini file.
        io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;

        ImGui_ImplWin32_Init(hwnd_);
        ImGui_ImplDX11_Init(device_.Get(), context_.Get());

        // Style.
        ImGuiStyle& style = ImGui::GetStyle();
        style.WindowRounding    = 0.f;
        style.WindowBorderSize  = 0.f;
        style.WindowPadding     = ImVec2(0.f, 0.f);
        style.Colors[ImGuiCol_WindowBg] = ImVec4(0.f, 0.f, 0.f, 0.f);

        return true;
    }

    // Begin a frame. Returns false if the game window is gone.
    bool begin_frame() {
        // Process window messages.
        MSG msg{};
        while (PeekMessageW(&msg, nullptr, 0, 0, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
            if (msg.message == WM_QUIT) return false;
        }

        // Track game window position/size.
        if (!sync_to_game_window()) return false;

        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();

        // Full-screen transparent ImGui window for drawing.
        ImGui::SetNextWindowPos(ImVec2(0, 0));
        ImGui::SetNextWindowSize(ImVec2(static_cast<float>(width_), static_cast<float>(height_)));
        ImGui::Begin("##esp", nullptr,
            ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoScrollbar |
            ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoBackground);

        return true;
    }

    void end_frame() {
        ImGui::End();
        ImGui::Render();

        const float clear_color[4] = {0.f, 0.f, 0.f, 0.f};
        context_->OMSetRenderTargets(1, rtv_.GetAddressOf(), nullptr);
        context_->ClearRenderTargetView(rtv_.Get(), clear_color);

        ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());
        swap_chain_->Present(1, 0); // VSync on.
    }

    int width()  const { return width_; }
    int height() const { return height_; }
    HWND hwnd()  const { return hwnd_; }

private:
    Config cfg_;
    HWND hwnd_ = nullptr;
    int  width_ = 1920, height_ = 1080;

    Microsoft::WRL::ComPtr<ID3D11Device>           device_;
    Microsoft::WRL::ComPtr<ID3D11DeviceContext>     context_;
    Microsoft::WRL::ComPtr<IDXGISwapChain>          swap_chain_;
    Microsoft::WRL::ComPtr<ID3D11RenderTargetView>  rtv_;

    bool create_device() {
        DXGI_SWAP_CHAIN_DESC sd{};
        sd.BufferCount        = 1;
        sd.BufferDesc.Width   = width_;
        sd.BufferDesc.Height  = height_;
        sd.BufferDesc.Format  = DXGI_FORMAT_R8G8B8A8_UNORM;
        sd.BufferDesc.RefreshRate.Numerator   = 0;
        sd.BufferDesc.RefreshRate.Denominator = 1;
        sd.BufferUsage        = DXGI_USAGE_RENDER_TARGET_OUTPUT;
        sd.OutputWindow       = hwnd_;
        sd.SampleDesc.Count   = 1;
        sd.Windowed           = TRUE;
        sd.SwapEffect         = DXGI_SWAP_EFFECT_DISCARD;

        D3D_FEATURE_LEVEL level;
        HRESULT hr = D3D11CreateDeviceAndSwapChain(
            nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr, 0,
            nullptr, 0, D3D11_SDK_VERSION,
            &sd, swap_chain_.GetAddressOf(), device_.GetAddressOf(),
            &level, context_.GetAddressOf()
        );
        if (FAILED(hr)) return false;

        return create_render_target();
    }

    bool create_render_target() {
        Microsoft::WRL::ComPtr<ID3D11Texture2D> back_buffer;
        if (FAILED(swap_chain_->GetBuffer(0, IID_PPV_ARGS(&back_buffer))))
            return false;
        return SUCCEEDED(device_->CreateRenderTargetView(back_buffer.Get(), nullptr, rtv_.GetAddressOf()));
    }

    bool sync_to_game_window() {
        HWND game = FindWindowW(
            cfg_.game_window_class.empty() ? nullptr : cfg_.game_window_class.c_str(),
            cfg_.game_window_title.empty() ? nullptr : cfg_.game_window_title.c_str()
        );
        if (!game || !IsWindow(game)) return false;

        RECT rc{};
        if (!GetClientRect(game, &rc)) return false;

        POINT pt{0, 0};
        ClientToScreen(game, &pt);

        int new_w = rc.right - rc.left;
        int new_h = rc.bottom - rc.top;

        if (new_w <= 0 || new_h <= 0) return false;

        // Move overlay to match.
        MoveWindow(hwnd_, pt.x, pt.y, new_w, new_h, TRUE);

        // Handle resize.
        if (new_w != width_ || new_h != height_) {
            width_  = new_w;
            height_ = new_h;

            rtv_.Reset();
            swap_chain_->ResizeBuffers(0, width_, height_, DXGI_FORMAT_UNKNOWN, 0);
            create_render_target();
        }

        return true;
    }

    void shutdown() {
        if (device_) {
            ImGui_ImplDX11_Shutdown();
            ImGui_ImplWin32_Shutdown();
            ImGui::DestroyContext();
        }
        rtv_.Reset();
        swap_chain_.Reset();
        context_.Reset();
        device_.Reset();
        if (hwnd_) { DestroyWindow(hwnd_); hwnd_ = nullptr; }
    }

    static LRESULT CALLBACK wnd_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
        if (ImGui_ImplWin32_WndProcHandler(hwnd, msg, wp, lp))
            return 0;
        if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
        return DefWindowProcW(hwnd, msg, wp, lp);
    }
};
