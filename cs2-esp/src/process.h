#pragma once
// ============================================================================
// CS2 ESP — Process & memory reader (external, ReadProcessMemory)
// ============================================================================

#include <Windows.h>
#include <TlHelp32.h>
#include <string>
#include <optional>
#include <cstdint>

class Process {
public:
    Process() = default;
    ~Process() { close(); }

    Process(const Process&) = delete;
    Process& operator=(const Process&) = delete;
    Process(Process&& o) noexcept
        : handle_(o.handle_), pid_(o.pid_) { o.handle_ = nullptr; o.pid_ = 0; }
    Process& operator=(Process&& o) noexcept {
        if (this != &o) { close(); handle_ = o.handle_; pid_ = o.pid_; o.handle_ = nullptr; o.pid_ = 0; }
        return *this;
    }

    // Attach to a running process by name. Returns false if not found.
    bool attach(const wchar_t* process_name) {
        close();
        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if (snap == INVALID_HANDLE_VALUE) return false;

        PROCESSENTRY32W pe{};
        pe.dwSize = sizeof(pe);
        bool found = false;

        if (Process32FirstW(snap, &pe)) {
            do {
                if (_wcsicmp(pe.szExeFile, process_name) == 0) {
                    pid_ = pe.th32ProcessID;
                    found = true;
                    break;
                }
            } while (Process32NextW(snap, &pe));
        }
        CloseHandle(snap);

        if (!found) return false;

        handle_ = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid_);
        return handle_ != nullptr;
    }

    // Check if the process is still alive.
    bool is_alive() const {
        if (!handle_) return false;
        DWORD code = 0;
        if (!GetExitCodeProcess(handle_, &code)) return false;
        return code == STILL_ACTIVE;
    }

    // Get base address and size of a module by name.
    struct ModuleInfo {
        uintptr_t base = 0;
        uint32_t  size = 0;
    };

    std::optional<ModuleInfo> get_module(const wchar_t* module_name) const {
        if (!handle_) return std::nullopt;

        HANDLE snap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, pid_);
        if (snap == INVALID_HANDLE_VALUE) return std::nullopt;

        MODULEENTRY32W me{};
        me.dwSize = sizeof(me);
        std::optional<ModuleInfo> result;

        if (Module32FirstW(snap, &me)) {
            do {
                if (_wcsicmp(me.szModule, module_name) == 0) {
                    result = ModuleInfo{
                        reinterpret_cast<uintptr_t>(me.modBaseAddr),
                        me.modBaseSize
                    };
                    break;
                }
            } while (Module32NextW(snap, &me));
        }
        CloseHandle(snap);
        return result;
    }

    // Read memory — returns false on partial read or failure.
    template <typename T>
    bool read(uintptr_t address, T& out) const {
        SIZE_T bytes_read = 0;
        if (!ReadProcessMemory(handle_, reinterpret_cast<LPCVOID>(address),
                               &out, sizeof(T), &bytes_read))
            return false;
        return bytes_read == sizeof(T);
    }

    // Read a raw buffer — returns false on partial read.
    bool read_raw(uintptr_t address, void* buffer, size_t size) const {
        SIZE_T bytes_read = 0;
        if (!ReadProcessMemory(handle_, reinterpret_cast<LPCVOID>(address),
                               buffer, size, &bytes_read))
            return false;
        return bytes_read == size;
    }

    // Read a null-terminated string with max length.
    std::string read_string(uintptr_t address, size_t max_len = 128) const {
        std::string buf(max_len, '\0');
        SIZE_T bytes_read = 0;
        if (!ReadProcessMemory(handle_, reinterpret_cast<LPCVOID>(address),
                               buf.data(), max_len, &bytes_read))
            return {};
        // Find null terminator
        size_t len = 0;
        while (len < bytes_read && buf[len] != '\0') ++len;
        buf.resize(len);
        return buf;
    }

    HANDLE handle() const { return handle_; }
    DWORD  pid()    const { return pid_; }

private:
    void close() {
        if (handle_) { CloseHandle(handle_); handle_ = nullptr; }
        pid_ = 0;
    }

    HANDLE handle_ = nullptr;
    DWORD  pid_    = 0;
};
