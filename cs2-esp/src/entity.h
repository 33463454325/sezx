#pragma once
// ============================================================================
// CS2 ESP — Entity reader
// ============================================================================
// Reads player data from the Source 2 entity system via external memory reads.
// Every read is validated: partial reads, null pointers and implausible values
// are rejected per-field. A missing offset gates only its own feature.
// ============================================================================

#include "process.h"
#include "offsets.h"
#include "math.h"
#include <vector>
#include <string>
#include <cstdint>

struct BonePos {
    Vec3 position;
};

struct PlayerData {
    std::string name;
    Vec3        position;       // feet
    Vec3        head_position;  // position + view offset (approximate head)
    Vec3        eye_angles;
    int         health      = 0;
    int         armor       = 0;
    int         team        = 0;
    bool        alive       = false;
    bool        has_helmet  = false;
    bool        is_scoped   = false;
    bool        is_spotted  = false;
    float       flash_duration = 0.f;
    float       distance    = 0.f; // from local player
    uint16_t    weapon_id   = 0;

    bool        has_bones   = false;
    std::vector<BonePos> bones;

    // Which fields are actually valid (offset was set and read succeeded).
    bool valid_position = false;
    bool valid_health   = false;
    bool valid_name     = false;
};

class EntityReader {
public:
    explicit EntityReader(const Process& proc) : proc_(proc) {}

    void set_client_base(uintptr_t base) { client_base_ = base; }

    // Read the view matrix from client.dll.
    bool read_view_matrix(ViewMatrix& vm) {
        if (!offsets::is_set(offsets::dwViewMatrix)) return false;
        return proc_.read(client_base_ + offsets::dwViewMatrix, vm);
    }

    // Read local player position (for distance calculations).
    bool read_local_player_pos(Vec3& out) {
        if (!offsets::is_set(offsets::dwLocalPlayerPawn)) return false;

        uintptr_t pawn = 0;
        if (!proc_.read(client_base_ + offsets::dwLocalPlayerPawn, pawn) || !pawn)
            return false;

        if (!offsets::is_set(offsets::m_pGameSceneNode) || !offsets::is_set(offsets::m_vecAbsOrigin))
            return false;

        uintptr_t scene_node = 0;
        if (!proc_.read(pawn + offsets::m_pGameSceneNode, scene_node) || !scene_node)
            return false;

        Vec3 pos{};
        if (!proc_.read(scene_node + offsets::m_vecAbsOrigin, pos))
            return false;

        if (!pos.is_plausible()) return false;
        out = pos;
        return true;
    }

    // Read the local player's team number.
    int read_local_team() {
        if (!offsets::is_set(offsets::dwLocalPlayerPawn) || !offsets::is_set(offsets::m_iTeamNum))
            return -1;

        uintptr_t pawn = 0;
        if (!proc_.read(client_base_ + offsets::dwLocalPlayerPawn, pawn) || !pawn)
            return -1;

        int team = 0;
        if (!proc_.read(pawn + offsets::m_iTeamNum, team))
            return -1;
        return team;
    }

    // Read all alive enemy (or all) players from the entity list.
    // max_index: cap the loop to prevent runaway reads.
    std::vector<PlayerData> read_players(const Vec3& local_pos, int local_team, int max_index = 64) {
        std::vector<PlayerData> result;
        if (!offsets::is_set(offsets::dwEntityList)) return result;

        uintptr_t entity_list = 0;
        if (!proc_.read(client_base_ + offsets::dwEntityList, entity_list) || !entity_list)
            return result;

        for (int i = 1; i <= max_index; ++i) {
            // Entity list is split into chunks of 512 entries.
            uintptr_t list_entry = 0;
            if (!proc_.read(entity_list + 0x8 * ((i & 0x7FFF) >> 9) + 0x10, list_entry) || !list_entry)
                continue;

            // Controller pointer from the entry.
            uintptr_t controller = 0;
            if (!proc_.read(list_entry + 0x78 * (i & 0x1FF), controller) || !controller)
                continue;

            PlayerData player{};

            // --- Team ---
            if (offsets::is_set(offsets::m_iTeamNum)) {
                proc_.read(controller + offsets::m_iTeamNum, player.team);
            }

            // Skip teammates (team 2 = T, team 3 = CT).
            if (player.team == local_team && player.team != 0)
                continue;

            // --- Alive check ---
            if (offsets::is_set(offsets::m_bPawnIsAlive)) {
                bool alive = false;
                proc_.read(controller + offsets::m_bPawnIsAlive, alive);
                if (!alive) continue;
            }

            // --- Name ---
            if (offsets::is_set(offsets::m_iszPlayerName)) {
                player.name = proc_.read_string(controller + offsets::m_iszPlayerName, 64);
                player.valid_name = !player.name.empty();
            }

            // --- Pawn handle → pawn pointer ---
            uintptr_t pawn = 0;
            if (offsets::is_set(offsets::m_hPlayerPawn)) {
                uint32_t pawn_handle = 0;
                if (!proc_.read(controller + offsets::m_hPlayerPawn, pawn_handle) || pawn_handle == 0xFFFFFFFF)
                    continue;

                // Resolve handle through entity list.
                uintptr_t pawn_entry = 0;
                if (!proc_.read(entity_list + 0x8 * ((pawn_handle & 0x7FFF) >> 9) + 0x10, pawn_entry) || !pawn_entry)
                    continue;
                if (!proc_.read(pawn_entry + 0x78 * (pawn_handle & 0x1FF), pawn) || !pawn)
                    continue;
            }

            // --- Health ---
            if (pawn && offsets::is_set(offsets::m_iHealth)) {
                if (proc_.read(pawn + offsets::m_iHealth, player.health)) {
                    player.valid_health = (player.health > 0 && player.health <= 100);
                    player.alive = player.health > 0;
                }
            }
            if (!player.alive) continue;

            // --- Life state double-check ---
            if (pawn && offsets::is_set(offsets::m_lifeState)) {
                uint8_t life_state = 1;
                proc_.read(pawn + offsets::m_lifeState, life_state);
                if (life_state != 0) continue;
            }

            // --- Position ---
            if (pawn && offsets::is_set(offsets::m_pGameSceneNode) && offsets::is_set(offsets::m_vecAbsOrigin)) {
                uintptr_t scene_node = 0;
                if (proc_.read(pawn + offsets::m_pGameSceneNode, scene_node) && scene_node) {
                    if (proc_.read(scene_node + offsets::m_vecAbsOrigin, player.position)) {
                        player.valid_position = player.position.is_plausible();
                    }
                }
            }
            if (!player.valid_position) continue;

            // --- Head / eye position ---
            if (pawn && offsets::is_set(offsets::m_vecViewOffset)) {
                Vec3 view_offset{};
                if (proc_.read(pawn + offsets::m_vecViewOffset, view_offset) && view_offset.is_finite()) {
                    player.head_position = player.position + view_offset;
                } else {
                    // Fallback: approximate head height for standing player.
                    player.head_position = player.position + Vec3{0.f, 0.f, 72.f};
                }
            } else {
                player.head_position = player.position + Vec3{0.f, 0.f, 72.f};
            }

            // --- Distance ---
            player.distance = distance_3d(local_pos, player.position);

            // --- Optional fields ---
            if (pawn && offsets::is_set(offsets::m_ArmorValue))
                proc_.read(pawn + offsets::m_ArmorValue, player.armor);
            if (pawn && offsets::is_set(offsets::m_bHasHelmet))
                proc_.read(pawn + offsets::m_bHasHelmet, player.has_helmet);
            if (pawn && offsets::is_set(offsets::m_angEyeAngles))
                proc_.read(pawn + offsets::m_angEyeAngles, player.eye_angles);
            if (pawn && offsets::is_set(offsets::m_bIsScoped))
                proc_.read(pawn + offsets::m_bIsScoped, player.is_scoped);
            if (pawn && offsets::is_set(offsets::m_flFlashDuration))
                proc_.read(pawn + offsets::m_flFlashDuration, player.flash_duration);

            // Spotted state (nested struct).
            if (pawn && offsets::is_set(offsets::m_entitySpottedState) && offsets::is_set(offsets::m_bSpotted)) {
                proc_.read(pawn + offsets::m_entitySpottedState + offsets::m_bSpotted, player.is_spotted);
            }

            // Weapon ID.
            if (pawn && offsets::is_set(offsets::m_pClippingWeapon)) {
                uintptr_t weapon = 0;
                if (proc_.read(pawn + offsets::m_pClippingWeapon, weapon) && weapon) {
                    if (offsets::is_set(offsets::m_AttributeManager) &&
                        offsets::is_set(offsets::m_Item) &&
                        offsets::is_set(offsets::m_iItemDefinitionIndex)) {
                        proc_.read(weapon + offsets::m_AttributeManager + offsets::m_Item + offsets::m_iItemDefinitionIndex,
                                   player.weapon_id);
                    }
                }
            }

            // --- Bones (optional) ---
            if (pawn && offsets::is_set(offsets::m_pGameSceneNode) && offsets::is_set(offsets::m_pBoneArray)) {
                uintptr_t scene_node = 0;
                if (proc_.read(pawn + offsets::m_pGameSceneNode, scene_node) && scene_node) {
                    uintptr_t bone_array = 0;
                    if (proc_.read(scene_node + offsets::m_pBoneArray, bone_array) && bone_array) {
                        // Each bone: 32 bytes (pos Vec3 + rot Quaternion), position at offset 0.
                        player.bones.resize(offsets::MAX_BONE_COUNT);
                        bool any_valid = false;
                        for (int b = 0; b < offsets::MAX_BONE_COUNT; ++b) {
                            Vec3 bpos{};
                            if (proc_.read(bone_array + b * 32, bpos) && bpos.is_plausible()) {
                                player.bones[b].position = bpos;
                                any_valid = true;
                            }
                        }
                        player.has_bones = any_valid;
                        if (!any_valid) player.bones.clear();
                    }
                }
            }

            result.push_back(std::move(player));
        }

        return result;
    }

private:
    const Process& proc_;
    uintptr_t client_base_ = 0;
};
