cmake_minimum_required(VERSION 3.20)
project(cs2-esp LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# --- ImGui (vendored in imgui/) ---
# Download imgui 1.90.4 headers + backends into cs2-esp/imgui/ before building.
# Required files:
#   imgui/imgui.h
#   imgui/imgui.cpp
#   imgui/imgui_draw.cpp
#   imgui/imgui_tables.cpp
#   imgui/imgui_widgets.cpp
#   imgui/imgui_demo.cpp          (optional, for the demo window)
#   imgui/backends/imgui_impl_win32.h
#   imgui/backends/imgui_impl_win32.cpp
#   imgui/backends/imgui_impl_dx11.h
#   imgui/backends/imgui_impl_dx11.cpp

set(IMGUI_DIR ${CMAKE_CURRENT_SOURCE_DIR}/imgui)

add_library(imgui STATIC
    ${IMGUI_DIR}/imgui.cpp
    ${IMGUI_DIR}/imgui_draw.cpp
    ${IMGUI_DIR}/imgui_tables.cpp
    ${IMGUI_DIR}/imgui_widgets.cpp
    ${IMGUI_DIR}/backends/imgui_impl_win32.cpp
    ${IMGUI_DIR}/backends/imgui_impl_dx11.cpp
)

target_include_directories(imgui PUBLIC
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
)

target_link_libraries(imgui PUBLIC d3d11 dxgi)

# --- Main executable ---
add_executable(cs2-esp WIN32
    src/main.cpp
)

target_include_directories(cs2-esp PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${IMGUI_DIR}
    ${IMGUI_DIR}/backends
)

target_link_libraries(cs2-esp PRIVATE
    imgui
    d3d11
    dxgi
)

# Console subsystem so we get printf output.
set_target_properties(cs2-esp PROPERTIES
    WIN32_EXECUTABLE FALSE
    OUTPUT_NAME "cs2-esp"
)
