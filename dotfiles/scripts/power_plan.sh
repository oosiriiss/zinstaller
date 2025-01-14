#!/bin/bash

get_current_power_plan() {
	currentplan=$(asusctl profile -p | tail -1 | awk '{print $NF}')
}

# If User is switching mode switch it before sending info to waybar
if [[ "$1" == "next" ]]; then
	asusctl profile -n
fi

get_current_power_plan

# MAIN monitor.. idk how this would work with multiple monitors
MONITOR=$(hyprctl monitors | grep "Monitor" | cut --delimiter=" " -f 2)

# disableing echo
stty -echo;
if [ "$currentplan" == "Balanced" ]; then
	text=""
	tooltip="Balanced"
	class="balanced"
	hyprctl keyword monitor $MONITOR,1920x1080@144.06,0x0,1  >> ~/.config/waybar/log.txt;
elif [ "$currentplan" == "Performance" ]; then
	text=""
	tooltip="Performance"
	class="performance"
	hyprctl keyword monitor $MONITOR,1920x1080@144.06,0x0,1 >> ~/.config/waybar/log.txt;
elif [ "$currentplan" == "Quiet" ]; then
	text=""
	tooltip="Quiet"
	class="quiet"
	hyprctl keyword monitor $MONITOR,1920x1080@60.06,0x0,1 >> ~/.config/waybar/log.txt;
fi

if [[ "$1" == "next" ]]; then
	pkill -SIGRTMIN+8 waybar;
	notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Power Profile: $currentplan"
fi
#Enablig echo
stty echo;
echo '{"text": "'$text'", "tooltip": "'Power plan: $tooltip'", "class": "'$class'"}'
