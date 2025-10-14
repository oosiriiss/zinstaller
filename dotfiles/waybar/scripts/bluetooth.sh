
CONTROLLER_INFO=$(bluetoothctl show)

POWERED_STATE=$(echo "$CONTROLLER_INFO" | grep -E "^.*Powered:.*$" | sed -E "s/^.*Powered: (.*)$/\1/")

# For possible future use
DISCOVERABLE_STATE=$(echo "$CONTROLLER_INFO" | grep -E "^.*Discoverable:.*$" | sed -E "s/^.*Discoverable: (.*)$/\1/")

# For possible future use
PAIRABLE_STATE=$(echo "$CONTROLLER_INFO" | grep -E "^.*Pairable:.*$" | sed -E "s/^.*Pairable: (.*)$/\1/")



# Toggling power
if [[ "$POWERED_STATE" == "yes" ]]; then
   bluetoothctl power off
else
   bluetoothctl power on 
fi
