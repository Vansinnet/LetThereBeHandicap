local mod = get_mod("LetThereBeHandicap")

return {
    name = mod:localize("mod_name"),
    description = mod:localize("mod_description"),
    is_togglable = true,
    allow_rehooking = true,
    options = {
        widgets = {
            {
                setting_id = "environment",
                type = "dropdown",
                default_value = "none",
                tooltip = "environment_tooltip",
                options = {
                    { text = "environment_none", value = "none" },
                    { text = "environment_inferno", value = "inferno" },
                    { text = "environment_power_interruption", value = "power_interruption" },
                    { text = "environment_fog", value = "fog" },
                    { text = "environment_noir", value = "noir" },
                    { text = "environment_random", value = "random" },
                },
            },
            {
                setting_id = "full_environment",
                type = "checkbox",
                default_value = true,
                tooltip = "full_environment_tooltip",
            },
            {
                setting_id = "show_terminal_button",
                type = "checkbox",
                default_value = true,
                tooltip = "show_terminal_button_tooltip",
            },
        },
    },
}
