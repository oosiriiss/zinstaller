hl.monitor(
	{
		output = "",
		mode = "preferred",
		scale = 1,

	}
)

-- Lanuching programs on start
hl.on("hyprland.start", function()
	local to_autostart_bg = {
		"/usr/lib/hyprpolkitagent/hyprpolkitagent", --  authenticating user when some program needs elevated privileges
		"waybar",
		"hyprpaper",
		"swaync",
		"hyprpaper"
	}

	for _, val in ipairs(to_autostart_bg) do
		hl.exec_cmd(val .. " &")
	end
end
)



require("animations")
require("binds")
require("decoration")
require("general")
require("env")
require("input")
require("misc")
