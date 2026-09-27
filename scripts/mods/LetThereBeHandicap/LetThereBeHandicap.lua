local mod = get_mod("LetThereBeHandicap")

local CircumstanceTemplates = require("scripts/settings/circumstance/circumstance_templates")
local Havoc = require("scripts/utilities/havoc")
local MissionTemplates = require("scripts/settings/mission/mission_templates")
local UISoundEvents = require("scripts/settings/ui/ui_sound_events")
local UIWidget = require("scripts/managers/ui/ui_widget")

local ENVIRONMENT_CYCLE = { "none", "inferno", "power_interruption", "fog", "noir", "random" }
local RANDOM_POOL = { "inferno", "power_interruption", "fog", "noir" }
local THEME_TAGS_BY_ENVIRONMENT = {
    inferno = { "ember" },
    power_interruption = { "darkness" },
    fog = { "ventilation_purge" },
    noir = { "noir", "dawn" },
}
local SUPPORTED_GAME_MODES = {
    coop_complete_objective = true,
}
local QUICKPLAY_IDS = {
    qp_mission_widget = true,
    campaign_playlist_upsell = true,
}
local MISSING_COLOR = "{#color(255,110,90)}"
local RESET_COLOR = "{#reset()}"

-- Mission terminal hint only, used when the level's _mission_themes resource is not readable
-- before the level package is loaded. Loading always uses the runtime file. Source: game 1.12.4.
local KNOWN_THEME_TAGS = {
    ["content/levels/dust/missions/mission_dm_propaganda"] = { darkness = true },
    ["content/levels/dust/missions/mission_hm_strain"] = { darkness = true, ember = true },
    ["content/levels/dust/missions/mission_lm_scavenge"] = { darkness = true },
    ["content/levels/entertainment/missions/mission_cm_raid"] = { darkness = true, ventilation_purge = true },
    ["content/levels/entertainment/missions/mission_fm_armoury"] = { darkness = true, ventilation_purge = true },
    ["content/levels/entertainment/missions/mission_km_heresy"] = { darkness = true, ventilation_purge = true },
    ["content/levels/tank_foundry/missions/mission_dm_forge"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/tank_foundry/missions/mission_fm_cargo"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/tank_foundry/missions/mission_lm_cooling"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/throneside/missions/mission_cm_archives"] = { darkness = true, ventilation_purge = true },
    ["content/levels/throneside/missions/mission_fm_resurgence"] = { darkness = true, ventilation_purge = true },
    ["content/levels/throneside/missions/mission_hm_complex"] = { darkness = true, ventilation_purge = true },
    ["content/levels/transit/missions/mission_cm_habs"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/transit/missions/mission_dm_rise"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/transit/missions/mission_km_station"] = { darkness = true, ember = true, noir = true, ventilation_purge = true },
    ["content/levels/transit/missions/mission_lm_rails"] = { darkness = true, ember = true, noir = true, ventilation_purge = true },
    ["content/levels/void/missions/mission_core_research"] = { darkness = true, ventilation_purge = true },
    ["content/levels/watertown/missions/mission_dm_stockpile"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/watertown/missions/mission_hm_cartel"] = { darkness = true, ember = true, ventilation_purge = true },
    ["content/levels/watertown/missions/mission_km_enforcer"] = { darkness = true, ember = true, ventilation_purge = true },
}

-- One override decision per mission load, latched in LevelLoader.start_loading so the
-- theme packages that are loaded always match the themes that are created.
local load_state = nil
local loader_phase = false
local fire_units = setmetatable({}, { __mode = "k" })
local message_delay = 0
local message_pending = false

local function runtime_mission_themes(level_name)
    local file_path = level_name .. "_mission_themes"

    if Application.can_get_resource("lua", file_path) then
        return require(file_path)
    end
end

local function first_available_tag(environment, mission_themes)
    local tags = THEME_TAGS_BY_ENVIRONMENT[environment]

    for i = 1, #tags do
        local tag = tags[i]

        if mission_themes[tag] then
            return tag
        end
    end
end

local function original_theme_tag(context)
    if context.havoc_data then
        return Havoc.parse_data(context.havoc_data).theme
    end

    local circumstance_template = context.circumstance_name and CircumstanceTemplates[context.circumstance_name]

    return circumstance_template and circumstance_template.theme_tag
end

local function resolve_override(state)
    local mission_themes = runtime_mission_themes(state.level_name) or {}
    local environment = state.environment

    if environment == "random" then
        local candidates = {}

        for i = 1, #RANDOM_POOL do
            local candidate = RANDOM_POOL[i]
            local tag = first_available_tag(candidate, mission_themes)

            if tag and tag ~= state.original_tag then
                candidates[#candidates + 1] = candidate
            end
        end

        if #candidates == 0 then
            state.status = "random_missing"

            return
        end

        environment = candidates[math.random(#candidates)]
    end

    state.resolved_environment = environment

    local tag = first_available_tag(environment, mission_themes)

    if not tag then
        state.status = "missing"
    elseif tag == state.original_tag then
        state.status = "already_active"
    else
        state.theme_tag = tag
        state.status = "pending"
    end
end

local function append_unique(target, seen, packages)
    for _, package_name in pairs(packages) do
        if not seen[package_name] then
            seen[package_name] = true
            target[#target + 1] = package_name
        end
    end
end

mod:hook_require("scripts/loading/loaders/level_loader", function(LevelLoader)
    mod:hook(LevelLoader, "start_loading", function(func, self, context)
        load_state = nil
        message_pending = false

        local environment = mod:get("environment")
        local mission_template = context and MissionTemplates[context.mission_name]

        if environment and environment ~= "none"
            and mission_template
            and SUPPORTED_GAME_MODES[mission_template.game_mode_name] then
            load_state = {
                level_name = mission_template.level or context.level_name,
                environment = environment,
                original_tag = original_theme_tag(context),
                full = mod:get("full_environment") ~= false,
            }
        end

        return func(self, context)
    end)

    mod:hook(LevelLoader, "_level_load_done_callback", function(func, self, ...)
        loader_phase = true

        local ok, result = pcall(func, self, ...)

        loader_phase = false

        if not ok then
            error(result, 0)
        end

        return result
    end)
end)

mod:hook_require("scripts/foundation/managers/package/utilities/theme_package", function(ThemePackage)
    mod:hook(ThemePackage, "level_resource_dependency_packages", function(func, level_name, theme_tag)
        local state = load_state

        if not loader_phase or not state or state.level_name ~= level_name then
            return func(level_name, theme_tag)
        end

        if not state.status then
            resolve_override(state)
        end

        local original_packages = func(level_name, theme_tag)

        if not state.theme_tag then
            return original_packages
        end

        -- The original themes stay in place until the level has spawned: themes affect which
        -- level units spawn, and the level must match the server's unit indices.
        local packages = {}
        local seen = {}

        append_unique(packages, seen, original_packages)

        state.override_packages = {}
        append_unique(state.override_packages, {}, func(level_name, state.theme_tag))
        append_unique(packages, seen, state.override_packages)

        return packages
    end)
end)

local function mark_desync()
    local state = load_state

    if state and not state.desync then
        state.desync = true
        mod:set("full_environment", false)
        mod:echo(MISSING_COLOR .. mod:localize("message_desync") .. RESET_COLOR)
    end
end

-- Full mode: the override themes are created right after the original ones, so they spawn with
-- the level (fires, sounds, theme lights). Object sets are still hidden as for the original
-- themes so the level matches the server as closely as possible.
local function hook_theme_state(ThemeState)
    mod:hook(ThemeState, "init", function(func, self, state_machine, shared_state)
        local result = func(self, state_machine, shared_state)
        local state = load_state

        if state and state.full and state.override_packages and state.status == "pending"
            and shared_state and shared_state.level_name == state.level_name then
            local ScriptTheme = require("scripts/foundation/utilities/script_theme")
            local world = shared_state.world
            local themes = shared_state.themes
            local override_packages = state.override_packages

            state.hide_sets = ScriptTheme.object_sets_to_hide(table.clone(themes))
            state.override_themes = {}

            for i = 1, #override_packages do
                local theme = World.create_theme(world, override_packages[i])

                themes[#themes + 1] = theme
                state.override_themes[i] = theme
            end

            state.debug_override_hide_sets = ScriptTheme.object_sets_to_hide(state.override_themes)
            state.themes_ref = themes
            state.status = "spawning"
        end

        return result
    end)
end

mod:hook_require("scripts/loading/local_states/local_theme_state", hook_theme_state)
mod:hook_require("scripts/loading/host_states/host_theme_state", hook_theme_state)

mod:hook_require("scripts/foundation/utilities/script_theme", function(ScriptTheme)
    mod:hook(ScriptTheme, "object_sets_to_hide", function(func, themes)
        local state = load_state

        if state and state.status == "spawning" and state.themes_ref == themes then
            return state.hide_sets
        end

        return func(themes)
    end)
end)

-- After the level has spawned, put the override themes first. Shading environments and light
-- groups are read from the first theme that defines them.
local function apply_override_themes(shared_state)
    local state = load_state

    if not (state and state.override_packages and shared_state and shared_state.level_name == state.level_name) then
        return
    end

    local themes = shared_state.themes

    if state.status == "spawning" then
        local override_themes = state.override_themes

        for i = 1, #override_themes do
            for j = #themes, 1, -1 do
                if themes[j] == override_themes[i] then
                    table.remove(themes, j)

                    break
                end
            end

            table.insert(themes, i, override_themes[i])
        end

        state.status = "applied"
    elseif state.status == "pending" then
        local world = shared_state.world
        local override_packages = state.override_packages

        for i = 1, #override_packages do
            table.insert(themes, i, World.create_theme(world, override_packages[i]))
        end

        state.status = "applied"
    end
end

mod:hook_require("scripts/loading/local_states/local_level_state", function(LocalLevelState)
    mod:hook(LocalLevelState, "update", function(func, self, dt)
        local result = func(self, dt)

        if result == "mission_load_done" then
            apply_override_themes(self._shared_state)
        end

        return result
    end)
end)

mod:hook_require("scripts/loading/host_states/host_level_state", function(HostLevelState)
    mod:hook(HostLevelState, "update", function(func, self, dt)
        local result = func(self, dt)

        if result == "load_done" then
            apply_override_themes(self._shared_state)
        end

        return result
    end)
end)

-- Full mode: the override themes spawn as the last nested levels, so their units come last in
-- Level.units. Leaving them out of the level unit registration keeps every level unit index and
-- the next free index identical to the server's, including for levels spawned later.
local function override_theme_units(level, state)
    local names = {}

    for i = 1, #state.override_packages do
        local package_name = state.override_packages[i]

        names[package_name] = true
        names[package_name .. ".level"] = true
    end

    local units = {}
    local nested_levels = Level.nested_levels(level)

    for i = 1, #nested_levels do
        local nested_level = nested_levels[i]

        if names[Level.name(nested_level)] then
            local nested_units = Level.units(nested_level, true)

            for j = 1, #nested_units do
                units[nested_units[j]] = true
            end
        end
    end

    return units
end

mod:hook_require("scripts/foundation/managers/unit_spawner/unit_spawner_manager", function(UnitSpawnerManager)
    mod:hook(UnitSpawnerManager, "register_static_level_spawned_units", function(func, self, level, units)
        local state = load_state

        if not (state and state.full and state.status == "applied" and not state.units_filtered) then
            return func(self, level, units)
        end

        state.units_filtered = true

        local excluded = override_theme_units(level, state)
        local filtered = {}

        for i = 1, #units do
            local unit = units[i]

            if not excluded[unit] then
                filtered[#filtered + 1] = unit
            end
        end

        state.excluded_unit_count = #units - #filtered

        return func(self, level, filtered)
    end)
end)

-- Desync guard for full mode: server RPCs address level units by index. If an index resolves to a
-- unit without the expected extension, the client level differs from the server's.
local function full_mode_active()
    local state = load_state

    return state and state.full and state.status == "applied"
end

local function level_unit_extension(system, unit_id, is_level_unit)
    local unit_spawner = Managers.state and Managers.state.unit_spawner
    local unit = unit_spawner and unit_spawner:unit(unit_id, is_level_unit)

    return unit and system._unit_to_extension_map[unit]
end

local function guard_rpc(system_class, rpc_name, level_unit_arg_is_flagged)
    mod:hook(system_class, rpc_name, function(func, self, channel_id, unit_id, arg3, ...)
        if full_mode_active() then
            local is_level_unit = true

            if level_unit_arg_is_flagged then
                is_level_unit = arg3
            end

            if is_level_unit and not level_unit_extension(self, unit_id, true) then
                mark_desync()

                return
            end
        end

        return func(self, channel_id, unit_id, arg3, ...)
    end)
end

mod:hook_require("scripts/extension_systems/destructible/destructible_system", function(DestructibleSystem)
    guard_rpc(DestructibleSystem, "rpc_destructible_damage_taken", true)
    guard_rpc(DestructibleSystem, "rpc_destructible_last_destruction", true)
    guard_rpc(DestructibleSystem, "rpc_sync_destructible", true)
end)

mod:hook_require("scripts/extension_systems/light_controller/light_controller_system", function(LightControllerSystem)
    guard_rpc(LightControllerSystem, "rpc_light_controller_set_enabled", false)
    guard_rpc(LightControllerSystem, "rpc_light_controller_set_flicker_state", false)
    guard_rpc(LightControllerSystem, "rpc_light_controller_hot_join", false)
end)

mod:hook_require("scripts/components/particle_effect", function(ParticleEffect)
    mod:hook(ParticleEffect, "init", function(func, self, unit)
        local particle_name = self:get_data(unit, "particle")

        if type(particle_name) == "string"
            and string.find(particle_name, "content/fx/particles/environment/", 1, true)
            and string.find(particle_name, "fire", 1, true) then
            fire_units[unit] = true
        end

        return func(self, unit)
    end)
end)

local function fire_unit_count()
    local count = 0

    for unit in pairs(fire_units) do
        if Unit.alive(unit) then
            count = count + 1
        end
    end

    return count
end

-- TEMPORARY diagnostics (remove before release): where do the override theme's units end up in
-- the level unit index order that the server uses?
local DEBUG_REPORT = true

mod:hook_require("scripts/game_states/game/gameplay_sub_states/gameplay_init_step_states/gameplay_init_step_extension_units", function(Step)
    mod:hook(Step, "_init_extension_unit_registration", function(func, self, world, shared_state, ...)
        local state = load_state

        if DEBUG_REPORT and state and state.status == "applied" and shared_state and shared_state.level then
            local level = shared_state.level
            local nested = Level.nested_levels(level)
            local parts = {}

            for i = 1, #nested do
                local ok, name = pcall(Level.name, nested[i])

                parts[#parts + 1] = tostring(ok and name or i) .. "=" .. #Level.units(nested[i], true)
            end

            state.debug_level = level
            state.debug_units = #Level.units(level, true)
            state.debug_direct_units = #Level.units(level)
            state.debug_nested = table.concat(parts, ", ")
        end

        return func(self, world, shared_state, ...)
    end)
end)

local function debug_report(state)
    if not DEBUG_REPORT or state.status ~= "applied" then
        return
    end

    local unit_spawner = Managers.state and Managers.state.unit_spawner
    local min_index, max_index, fire_count, nested_fire = nil, nil, 0, 0

    for unit in pairs(fire_units) do
        if Unit.alive(unit) then
            fire_count = fire_count + 1

            local index = unit_spawner and unit_spawner:level_index(unit)

            if index then
                min_index = math.min(min_index or index, index)
                max_index = math.max(max_index or index, index)
            end

            if Unit.level(unit) ~= state.debug_level then
                nested_fire = nested_fire + 1
            end
        end
    end

    local line = string.format("LTBH debug: mode=%s units=%s direct=%s nested=[%s] fires=%d fire_idx=%s-%s fire_outside_main_level=%d excluded=%s",
        state.full and "full" or "visual", tostring(state.debug_units), tostring(state.debug_direct_units),
        tostring(state.debug_nested), fire_count, tostring(min_index), tostring(max_index), nested_fire,
        tostring(state.excluded_unit_count))

    local function join(list)
        local parts = {}

        for i = 1, #(list or {}) do
            parts[i] = tostring(list[i])
        end

        return table.concat(parts, ", ")
    end

    local hide_line = string.format("LTBH debug hide sets: original=[%s] override=[%s]",
        join(state.hide_sets), join(state.debug_override_hide_sets))

    mod:info(line)
    mod:echo(line)
    mod:info(hide_line)
    mod:echo(hide_line)
end

local function environment_name(environment)
    return mod:localize("environment_" .. tostring(environment))
end

local function load_message(state)
    local status = state.status
    local environment = state.resolved_environment or state.environment

    if status == "applied" then
        local message

        if state.environment == "random" then
            message = mod:localize("message_random_applied", environment_name(environment))
        else
            message = mod:localize("message_applied", environment_name(environment))
        end

        if environment == "inferno" then
            if not state.full then
                message = message .. " " .. mod:localize("message_fires_visual_only")
            elseif fire_unit_count() == 0 then
                message = message .. " " .. MISSING_COLOR .. mod:localize("message_fires_missing") .. RESET_COLOR
            end
        end

        return message
    elseif status == "missing" then
        return MISSING_COLOR .. mod:localize("message_missing", environment_name(environment)) .. RESET_COLOR
    elseif status == "random_missing" then
        return MISSING_COLOR .. mod:localize("message_random_missing") .. RESET_COLOR
    elseif status == "already_active" then
        return mod:localize("message_already_active", environment_name(environment))
    end

    return MISSING_COLOR .. mod:localize("message_not_applied", environment_name(environment)) .. RESET_COLOR
end

mod.on_game_state_changed = function(status, state_name)
    if state_name ~= "StateGameplay" then
        return
    end

    if status == "enter" then
        message_pending = load_state ~= nil
        message_delay = 3
    else
        message_pending = false
        load_state = nil
    end
end

mod.update = function(dt)
    if not message_pending or not mod:is_enabled() then
        return
    end

    if not (Managers.state and Managers.state.circumstance) then
        return
    end

    -- Level components (fires) finish initializing shortly after gameplay starts.
    message_delay = message_delay - (dt or 0)

    if message_delay > 0 then
        return
    end

    message_pending = false

    if load_state then
        mod:echo(load_message(load_state))
        debug_report(load_state)
    end
end

-- Mission terminal button

local BUTTON_SIZE = { 336, 52 }

local function button_visible()
    return mod:is_enabled() and mod:get("show_terminal_button")
end

local function mission_themes_for_level(level_name)
    return runtime_mission_themes(level_name) or KNOWN_THEME_TAGS[level_name] or {}
end

local function availability_hint(view, environment)
    if environment == "none" then
        return mod:localize("hint_none")
    end

    local mission_id = view._selected_mission_id

    if mission_id == nil then
        return ""
    elseif QUICKPLAY_IDS[mission_id] then
        return mod:localize("hint_quickplay")
    end

    local mission = view:_mission(mission_id, true)
    local mission_template = mission and MissionTemplates[mission.map]

    if not mission_template or not SUPPORTED_GAME_MODES[mission_template.game_mode_name] then
        return ""
    end

    local mission_themes = mission_themes_for_level(mission_template.level)

    if environment == "random" then
        local names = {}

        for i = 1, #RANDOM_POOL do
            if first_available_tag(RANDOM_POOL[i], mission_themes) then
                names[#names + 1] = environment_name(RANDOM_POOL[i])
            end
        end

        if #names == 0 then
            return mod:localize("hint_random_missing")
        end

        return mod:localize("hint_random", table.concat(names, ", "))
    end

    if first_available_tag(environment, mission_themes) then
        return mod:localize("hint_available")
    end

    return mod:localize("hint_missing")
end

local function next_environment(environment)
    for i = 1, #ENVIRONMENT_CYCLE do
        if ENVIRONMENT_CYCLE[i] == environment then
            return ENVIRONMENT_CYCLE[i % #ENVIRONMENT_CYCLE + 1]
        end
    end

    return ENVIRONMENT_CYCLE[1]
end

mod:hook_require("scripts/ui/views/mission_board_view/mission_board_view_definitions", function(definitions)
    definitions.scenegraph_definition.ltbh_environment_button = {
        horizontal_alignment = "center",
        parent = "play_button",
        vertical_alignment = "bottom",
        size = BUTTON_SIZE,
        position = {
            0,
            BUTTON_SIZE[2] + 8,
            1,
        },
    }

    definitions.widget_definitions.ltbh_environment_button = UIWidget.create_definition({
        {
            pass_type = "hotspot",
            content_id = "hotspot",
            content = {
                on_hover_sound = UISoundEvents.default_mouse_hover,
                on_pressed_sound = UISoundEvents.default_click,
            },
            visibility_function = button_visible,
        },
        {
            pass_type = "rect",
            style_id = "background",
            style = {
                color = { 190, 12, 16, 12 },
                offset = { 0, 0, 0 },
            },
            change_function = function(content, style)
                local hover_progress = content.hotspot.anim_hover_progress or 0

                style.color[1] = 190 + 65 * hover_progress
            end,
            visibility_function = button_visible,
        },
        {
            pass_type = "text",
            value_id = "text",
            style_id = "text",
            value = "",
            style = {
                font_type = "proxima_nova_bold",
                font_size = 20,
                text_horizontal_alignment = "center",
                text_vertical_alignment = "top",
                text_color = { 255, 226, 199, 126 },
                offset = { 0, 5, 2 },
            },
            visibility_function = button_visible,
        },
        {
            pass_type = "text",
            value_id = "hint",
            style_id = "hint",
            value = "",
            style = {
                font_type = "proxima_nova_bold",
                font_size = 15,
                text_horizontal_alignment = "center",
                text_vertical_alignment = "bottom",
                text_color = { 255, 169, 191, 153 },
                offset = { 0, -5, 2 },
            },
            visibility_function = button_visible,
        },
    }, "ltbh_environment_button")
end)

mod:hook_require("scripts/ui/views/mission_board_view/mission_board_view", function(MissionBoardView)
    mod:hook_safe(MissionBoardView, "update", function(self)
        local widget = self._widgets_by_name and self._widgets_by_name.ltbh_environment_button

        if not widget then
            return
        end

        local content = widget.content
        local environment = mod:get("environment") or "none"
        local hotspot = content.hotspot

        if hotspot and hotspot.on_pressed then
            hotspot.on_pressed = false

            if button_visible() then
                environment = next_environment(environment)
                mod:set("environment", environment)
            end
        end

        local mission_id = self._selected_mission_id

        if content.ltbh_environment ~= environment or content.ltbh_mission_id ~= mission_id then
            content.ltbh_environment = environment
            content.ltbh_mission_id = mission_id
            content.text = mod:localize("button_label", environment_name(environment))
            content.hint = availability_hint(self, environment)
        end
    end)
end)
