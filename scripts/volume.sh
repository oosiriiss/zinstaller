
# The grep of Thats why it doesn't work sometimes Default sink is different depending on the language of the system
currentOutput=$(pactl info | grep "Default Sink" | cut -f3 -d" ")

if [[ "$1" == "mt" ]]; then 
	pactl set-sink-mute $currentOutput toggle
elif [[ "$1" == "vu" ]]; then 
	pactl set-sink-volume $currentOutput +1%
elif [[ "$1" == "vd" ]]; then 
	pactl set-sink-volume $currentOutput -1%
fi

