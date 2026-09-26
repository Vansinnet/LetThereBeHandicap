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
local theme_phase = false
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

        if not state or state.level_name ~= level_name then
            return func(level_name, theme_tag)
        end

        if loader_phase then
            if not state.status then
                resolve_override(state)
            end

            local original_packages = func(level_name, theme_tag)

            if not state.theme_tag then
                return original_packages
            end

            -- Load the original theme too: its hide sets are needed so the client spawns
            -- the same level objects as the server.
            local packages = {}
            local seen = {}

            append_unique(packages, seen, original_packages)
            state.original_packages = table.clone(packages)
            append_unique(packages, seen, func(level_name, state.theme_tag))
            state.packages_loaded = true

            return packages
        end

        if theme_phase and state.packages_loaded then
            return func(level_name, state.theme_tag)
        end

        return func(level_name, theme_tag)
    end)
end)

local function capture_original_hide_sets(state, shared_state)
    local ScriptTheme = require("scripts/foundation/utilities/script_theme")
    local world = shared_state.world
    local original_packages = state.original_packages
    local original_themes = {}

    for i = 1, #original_packages do
        original_themes[i] = World.create_theme(world, original_packages[i])
    end

    state.hide_sets = ScriptTheme.object_sets_to_hide(original_themes)

    for i = 1, #original_themes do
        World.destroy_theme(world, original_themes[i])
    end

    state.themes_ref = shared_state.themes
    state.status = "applied"
end

local function hook_theme_state(ThemeState)
    mod:hook(ThemeState, "init", function(func, self, state_machine, shared_state)
        local state = load_state

        if not (state and state.packages_loaded and shared_state and shared_state.level_name == state.level_name) then
            return func(self, state_machine, shared_state)
        end

        theme_phase = true

        local ok, result = pcall(func, self, state_machine, shared_state)

        theme_phase = false

        if not ok then
            error(result, 0)
        end

        capture_original_hide_sets(state, shared_state)

        return result
    end)
end

mod:hook_require("scripts/loading/local_states/local_theme_state", hook_theme_state)
mod:hook_require("scripts/loading/host_states/host_theme_state", hook_theme_state)

mod:hook_require("scripts/foundation/utilities/script_theme", function(ScriptTheme)
    mod:hook(ScriptTheme, "object_sets_to_hide", function(func, themes)
        local state = load_state

        if state and state.themes_ref ~= nil and state.themes_ref == themes then
            return state.hide_sets
        end

        return func(themes)
    end)
end)

local function environment_name(environment)
    return mod:localize("environment_" .. tostring(environment))
end

local function load_message(state)
    local status = state.status
    local environment = state.resolved_environment or state.environment

    if status == "applied" then
        if state.environment == "random" then
            return mod:localize("message_random_applied", environment_name(environment))
        end

        return mod:localize("message_applied", environment_name(environment))
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
    else
        message_pending = false
        load_state = nil
    end
end

mod.update = function()
    if not message_pending or not mod:is_enabled() then
        return
    end

    if not (Managers.state and Managers.state.circumstance) then
        return
    end

    message_pending = false

    if load_state then
        mod:echo(load_message(load_state))
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
