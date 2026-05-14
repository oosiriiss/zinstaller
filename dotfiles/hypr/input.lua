hl.config(
	{
		input = {
			kb_layout = "pl",
			sensitivity = 0,

			touchpad = {
				natural_scroll = true
			}
		}
	}
)


hl.gesture(
	{
		fingers = 3,
		direction = "horizontal",
		action = "workspace"
	}
)


hl.gesture(
	{
		fingers = 3,
		direction = "swipe",
		action = "resize",
		mods = "SUPER",
	}
)


