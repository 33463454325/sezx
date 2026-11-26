cmake_minimum_required(VERSION 3.22)
project(vektor LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_compile_options(-fvisibility=hidden -fno-rtti -fno-exceptions
                    -Wall -Wextra -Wno-unused-parameter -Wno-unused-function)
add_compile_definitions(IMGUI_IMPL_OPENGL_ES3)

include(FetchContent)
set(FETCHCONTENT_QUIET OFF)

FetchContent_Declare(imgui
  GIT_REPOSITORY https://github.com/ocornut/imgui.git
  GIT_TAG v1.90.4)
FetchContent_MakeAvailable(imgui)

add_library(imgui_vektor STATIC
  ${imgui_SOURCE_DIR}/imgui.cpp
  ${imgui_SOURCE_DIR}/imgui_draw.cpp
  ${imgui_SOURCE_DIR}/imgui_tables.cpp
  ${imgui_SOURCE_DIR}/imgui_widgets.cpp
  ${imgui_SOURCE_DIR}/backends/imgui_impl_opengl3.cpp)
target_include_directories(imgui_vektor PUBLIC
  ${imgui_SOURCE_DIR} ${imgui_SOURCE_DIR}/backends)

add_library(vektor SHARED
  src/entry.cpp
  src/hooks.cpp
  src/gles_hook.cpp
  src/menu.cpp)

target_include_directories(vektor PRIVATE src)
target_link_libraries(vektor PRIVATE imgui_vektor log EGL GLESv3 android)
set_target_properties(vektor PROPERTIES OUTPUT_NAME "vektor")
