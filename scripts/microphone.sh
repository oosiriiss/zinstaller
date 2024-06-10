

currentInput=$(pactl info | grep "Default Source" | cut -f3 -d" ")

if [[ "$1" == "mt" ]]; then 
	pactl set-source-mute $currentInput toggle
elif [[ "$1" == "vu" ]]; then 
	pactl set-source-volume $currentInput +1%
elif [[ "$1" == "vd" ]]; then 
	pactl set-source-volume $currentInput -1%
fi

