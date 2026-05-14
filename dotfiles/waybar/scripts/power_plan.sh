#!/bin/bash



currentplan=$(/usr/bin/python3 /usr/bin/powerprofilesctl get)

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


   /usr/bin/python3 /usr/bin/powerprofilesctl set "$next"

fi

currentplan=$(/usr/bin/python3 /usr/bin/powerprofilesctl get)

# MAIN monitor.. idk how this would work with multiple monitors
MONITOR=$(hyprctl monitors | grep "Monitor" | cut --delimiter=" " -f 2)
# Preserving all previous monitor data
MONITOR_JSON=$(hyprctl monitors -j | jq -r ".[] | select(.name == \"$MONITOR\")")
MONITOR_RES_X=$(echo "$MONITOR_JSON" | jq -r ".width")
MONITOR_RES_Y=$(echo "$MONITOR_JSON" | jq -r ".height")
MONITOR_OFF_X=$(echo "$MONITOR_JSON" | jq -r ".x")
MONITOR_OFF_Y=$(echo "$MONITOR_JSON" | jq -r ".y")
MONITOR_SCALE=$(echo "$MONITOR_JSON" | jq -r ".scale")


# disabling echo
if [ "$currentplan" == "balanced" ]; then
	PLAN_NAME="Balanced"
	CLASS="balanced"
        TARGET_MODE="highrr"
elif [ "$currentplan" == "performance" ]; then
	PLAN_NAME="Performance"
	CLASS="performance"
        TARGET_MODE="highrr"
elif [ "$currentplan" == "power-saver" ]; then
	PLAN_NAME="Power saver"
	CLASS="power-saver"
        TARGET_MODE="${MONITOR_RES_X}x${MONITOR_RES_Y}@60.06"
fi

# Changing framerate
MONITOR_LUA_PAYLOAD="
hl.monitor(
   {
      output = '$MONITOR',
      mode = '$TARGET_MODE',
      position = '${MONITOR_OFF_X}x${MONITOR_OFF_Y}',
      scale = $MONITOR_SCALE
   }
)
"

# TODO FIXME :: the framerat echanges in hyprland, but visually it stays the same

hyprctl eval "hl.monitor({ output = '${MONITOR}', mode = '${TARGET_MODE}', position = '${MONITOR_OFF_X}x${MONITOR_OFF_Y}', scale = ${MONITOR_SCALE} })" >> ~/.config/waybar/log.txt


if [[ "$1" == "next" ]]; then
	pkill -SIGRTMIN+8 waybar;
	notify-send -h string:x-canonical-private-synchronous:sys-notify -u low "Power Profile: $currentplan"
fi

readonly OUTPUT="{\"text\":\"$PLAN_NAME\", \"alt\": \"$CLASS\", \"tooltip\": \"Power plan: $PLAN_NAME\", \"class\": \"$CLASS\"}"

echo "$OUTPUT" >> ~/.config/waybar/log.txt
echo "$OUTPUT";
