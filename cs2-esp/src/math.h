#pragma once
// ============================================================================
// CS2 ESP — Math utilities (pure functions, no game dependency)
// ============================================================================
// Coordinate system: Source 2 — right-handed, Z-up.
// ViewMatrix: row-major 4×4, as read from client.dll.
// ============================================================================

#include <cmath>
#include <optional>

struct Vec2 {
    float x = 0.f, y = 0.f;
};

struct Vec3 {
    float x = 0.f, y = 0.f, z = 0.f;

    Vec3 operator+(const Vec3& o) const { return {x + o.x, y + o.y, z + o.z}; }
    Vec3 operator-(const Vec3& o) const { return {x - o.x, y - o.y, z - o.z}; }
    Vec3 operator*(float s)       const { return {x * s, y * s, z * s}; }

    float length() const { return std::sqrtf(x * x + y * y + z * z); }

    bool is_finite() const {
        return std::isfinite(x) && std::isfinite(y) && std::isfinite(z);
    }

    bool is_plausible(float max_coord = 32768.f) const {
        return is_finite()
            && std::fabsf(x) < max_coord
            && std::fabsf(y) < max_coord
            && std::fabsf(z) < max_coord;
    }
};

// Row-major 4×4 view-projection matrix as Source 2 stores it.
struct ViewMatrix {
    float m[4][4]{};
};

// World-to-screen projection.
// Returns std::nullopt if the point is behind the camera.
// screen_w / screen_h: viewport dimensions in pixels.
inline std::optional<Vec2> world_to_screen(
    const Vec3& pos,
    const ViewMatrix& vm,
    int screen_w,
    int screen_h)
{
    // Clip-space W
    float w = vm.m[3][0] * pos.x + vm.m[3][1] * pos.y + vm.m[3][2] * pos.z + vm.m[3][3];
    if (w < 0.001f)
        return std::nullopt; // behind camera

    float inv_w = 1.0f / w;

    float nx = (vm.m[0][0] * pos.x + vm.m[0][1] * pos.y + vm.m[0][2] * pos.z + vm.m[0][3]) * inv_w;
    float ny = (vm.m[1][0] * pos.x + vm.m[1][1] * pos.y + vm.m[1][2] * pos.z + vm.m[1][3]) * inv_w;

    float sx = (screen_w * 0.5f) + (nx * screen_w * 0.5f);
    float sy = (screen_h * 0.5f) - (ny * screen_h * 0.5f);

    return Vec2{sx, sy};
}

// Distance between two 3D points.
inline float distance_3d(const Vec3& a, const Vec3& b) {
    return (a - b).length();
}
