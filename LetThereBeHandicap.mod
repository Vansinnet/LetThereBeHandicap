return {
    run = function()
        fassert(rawget(_G, "new_mod"), "`LetThereBeHandicap` failed loading DMF.")
        new_mod("LetThereBeHandicap", {
            mod_script = "LetThereBeHandicap/scripts/mods/LetThereBeHandicap/LetThereBeHandicap",
            mod_data = "LetThereBeHandicap/scripts/mods/LetThereBeHandicap/LetThereBeHandicap_data",
            mod_localization = "LetThereBeHandicap/scripts/mods/LetThereBeHandicap/LetThereBeHandicap_localization",
        })
    end,
    packages = {},
}
