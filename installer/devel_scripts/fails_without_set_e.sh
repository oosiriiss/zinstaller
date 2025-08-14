# This script should pass the setup stage. as a failing command doesn't terminate the script with nonzero code
echo 1
echo 2
echo 3
echo "Failing but shouldn't terminate... 'OK' Message will be displayed if it worked."
false
echo "OK"

