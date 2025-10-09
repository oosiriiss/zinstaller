#!/bin/bash

currentplan=$(powerprofilesctl get)

# If User is switching mode switch it before sending info to waybar
if [[ "$1" == "next" ]]; then

   profiles=(power-saver balanced performance)

   # Finding index 
   for i in "${!profiles[@]}"; do
      if [[ "${profiles[$i]}" == "$currentplan" ]]; then
	 index=$i
	 break
      fi
   done

   next_index=$(( (index + 1) % ${#profiles[@]} ))
      next="${profiles[$next_index]}"
   
   powerprofilesctl set "$next"

fi

currentplan=$(powerprofilesctl get)

# MAIN monitor.. idk how this would work with multiple monitors
MONITOR=$(hyprctl monitors | grep "Monitor" | cut --delimiter=" " -f 2)

# disabling echo
if [ "$currentplan" == "balanced" ]; then
	planname="Balanced"
	class="balanced"
	hyprctl keyword monitor $MONITOR,1920x1080@144.06,0x0,1  >> ~/.config/waybar/log.txt;
elif [ "$currentplan" == "performance" ]; then
	planname="Performance"
	class="performance"
	hyprctl keyword monitor $MONITOR,1920x1080@144.06,0x0,1 >> ~/.config/waybar/log.txt;
elif [ "$currentplan" == "power-saver" ]; then
	planname="Power saver"
	class="power-saver"
	hyprctl keyword monitor $MONITOR,1920x1080@60.06,0x0,1 >> ~/.config/waybar/log.txt;
fi

if [[ "$1" == "next" ]]; then
	pkill -SIGRTMIN+8 waybar;
	notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Power Profile: $currentplan"
fi
#Enablig echo

readonly OUTPUT="{\"text\":\"$planname\", \"alt\": \"$class\", \"tooltip\": \"Power plan: $planname\", \"class\": \"$class\"}"

echo "$OUTPUT" >> ~/.config/waybar/log.txt
echo "$OUTPUT";
