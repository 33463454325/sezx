#pragma once
// ============================================================================
// CS2 ESP — Offset Configuration
// ============================================================================
// BUILD: UNKNOWN — populate from cs2-dumper or Dumper-7 for your game build.
// Every offset is an RVA (relative virtual address from module base) unless
// noted otherwise. OFFSET_UNKNOWN gates its feature at runtime.
// ============================================================================

#include <cstdint>
#include <optional>

namespace offsets {

// Sentinel: distinguishes "not yet filled in" from a real zero offset.
inline constexpr uint32_t UNKNOWN = 0xDEAD;

// ---------------------------------------------------------------------------
// How to populate these offsets
// ---------------------------------------------------------------------------
// 1. Run cs2-dumper (https://github.com/a2x/cs2-dumper) on your build.
//    It outputs offsets.json / offsets.hpp with everything below.
// 2. Alternatively, run Dumper-7 / UE4SS-style schema dumper for Source 2.
// 3. Manual: in IDA/Ghidra, search client.dll for the string references
//    noted next to each offset, then xref to find the access pattern.
//
// After populating, set build_id to match your cs2 executable's build number
// (shown in-game under Settings → About or via SteamDB).
// ---------------------------------------------------------------------------

// Game build this config was dumped from.
inline const char* build_id = "UNKNOWN";

// --- client.dll -----------------------------------------------------------

// dwEntityList: xref string "m_pEntity" or pattern scan in client.dll.
// cs2-dumper key: client.dll → dwEntityList
inline uint32_t dwEntityList       = UNKNOWN;

// dwLocalPlayerController: xref "LocalPlayerController" string.
// cs2-dumper key: client.dll → dwLocalPlayerController
inline uint32_t dwLocalPlayerController = UNKNOWN;

// dwViewMatrix: xref "ViewMatrix" or scan for the 4x4 float matrix write.
// cs2-dumper key: client.dll → dwViewMatrix
inline uint32_t dwViewMatrix       = UNKNOWN;

// dwLocalPlayerPawn: xref "m_hPawn" on the local player controller.
// cs2-dumper key: client.dll → dwLocalPlayerPawn
inline uint32_t dwLocalPlayerPawn  = UNKNOWN;

// --- C_BaseEntity / CGameSceneNode ----------------------------------------

// m_hPlayerPawn: CCSPlayerController → m_hPlayerPawn
// Schema: CCSPlayerController → m_hPlayerPawn
inline uint32_t m_hPlayerPawn      = UNKNOWN;

// m_iHealth: C_BaseEntity → m_iHealth
inline uint32_t m_iHealth          = UNKNOWN;

// m_iTeamNum: C_BaseEntity → m_iTeamNum
inline uint32_t m_iTeamNum         = UNKNOWN;

// m_lifeState: C_BaseEntity → m_lifeState (0 = alive)
inline uint32_t m_lifeState        = UNKNOWN;

// m_pGameSceneNode: C_BaseEntity → m_pGameSceneNode (pointer to scene node)
inline uint32_t m_pGameSceneNode   = UNKNOWN;

// m_vecAbsOrigin: CGameSceneNode → m_vecAbsOrigin (Vector3: x, y, z)
inline uint32_t m_vecAbsOrigin     = UNKNOWN;

// m_vecViewOffset: C_BaseModelEntity → m_vecViewOffset (eye offset from origin)
inline uint32_t m_vecViewOffset    = UNKNOWN;

// m_iszPlayerName: CCSPlayerController → m_iszPlayerName
inline uint32_t m_iszPlayerName    = UNKNOWN;

// m_bPawnIsAlive: CCSPlayerController → m_bPawnIsAlive
inline uint32_t m_bPawnIsAlive     = UNKNOWN;

// m_ArmorValue: CCSPlayerController pawn → m_ArmorValue
inline uint32_t m_ArmorValue       = UNKNOWN;

// m_bHasHelmet: pawn → m_bHasHelmet
inline uint32_t m_bHasHelmet       = UNKNOWN;

// m_angEyeAngles: C_CSPlayerPawnBase → m_angEyeAngles (pitch, yaw, roll)
inline uint32_t m_angEyeAngles     = UNKNOWN;

// m_entitySpottedState + m_bSpotted: C_CSPlayerPawn → spotted state
inline uint32_t m_entitySpottedState = UNKNOWN;
inline uint32_t m_bSpotted         = UNKNOWN; // offset within the spotted-state struct

// m_pClippingWeapon: C_CSPlayerPawnBase → m_pClippingWeapon (active weapon ptr)
inline uint32_t m_pClippingWeapon  = UNKNOWN;

// m_AttributeManager + m_Item + m_iItemDefinitionIndex: weapon → item def index
inline uint32_t m_AttributeManager          = UNKNOWN;
inline uint32_t m_Item                      = UNKNOWN;
inline uint32_t m_iItemDefinitionIndex      = UNKNOWN;

// m_flFlashDuration: C_CSPlayerPawnBase → m_flFlashDuration
inline uint32_t m_flFlashDuration  = UNKNOWN;

// m_bIsScoped: C_CSPlayerPawn → m_bIsScoped
inline uint32_t m_bIsScoped        = UNKNOWN;

// --- Bone data (optional — for skeleton ESP) ------------------------------
// m_pBoneArray: CSkeletonInstance (from scene node) → bone array pointer
// Usually at CGameSceneNode + 0x1F0 → CSkeletonInstance, then
// CSkeletonInstance + bone_array_offset → array of CBoneData (pos + rot)
inline uint32_t m_pBoneArray       = UNKNOWN;

// Number of bones for CT/T player models is typically 128+, but we cap reads.
inline constexpr int MAX_BONE_COUNT = 128;

// --- Helpers --------------------------------------------------------------
inline bool is_set(uint32_t off) { return off != UNKNOWN; }

} // namespace offsets
