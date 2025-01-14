

currentInput=$(pactl get-default-source)

if [[ "$1" == "mt" ]]; then 
	pactl set-source-mute $currentInput toggle
elif [[ "$1" == "vu" ]]; then 
	pactl set-source-volume $currentInput +1%
elif [[ "$1" == "vd" ]]; then 
	pactl set-source-volume $currentInput -1%
fi

