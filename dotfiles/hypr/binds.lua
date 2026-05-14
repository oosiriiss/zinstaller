local vars = require("vars")

local mainMod = vars.main_mod
local fileManager = vars.file_manager
local program_menu = vars.program_menu
local terminal = vars.terminal

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(program_menu))
hl.bind(mainMod .. " + CONTROL + ALT + Q", hl.dsp.exit())
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())

-- Moving to workspace and moving active window between workspaces
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scratchpad special workspace
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))


hl.bind("XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("~/.config/waybar/scripts/volume.sh vu", { locked = true, repeating = true }))
hl.bind("XF86AudioLowerVolume",
	hl.dsp.exec_cmd("~/.config/waybar/scripts/volume.sh vd", { locked = true, repeating = true }))

hl.bind("XF86AudioMute",
	hl.dsp.exec_cmd("~/.config/waybar/scripts/volume.sh mt", { locked = true, repeating = false }))
hl.bind("XF86AudioMicMute",
	hl.dsp.exec_cmd("~/.config/waybar/scripts/microphone.sh mt", { locked = true, repeating = false }))


hl.bind("XF86MonBrightnessDown",
	hl.dsp.exec_cmd("brightnessctl s 1%-", { locked = true, repeating = true }))
hl.bind("XF86MonBrightnessUp",
	hl.dsp.exec_cmd("brightnessctl s +1%", { locked = true, repeating = true }))
