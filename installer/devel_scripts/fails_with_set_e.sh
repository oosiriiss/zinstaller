# This script should fail pass stage as there is a failing command with bash -e flag.
set -e

echo 1
echo 2
echo 3
echo "Failing with -e flag. 'FAILED' will be displayed if it doesn't exit."
false
echo "FAILED"
echo 4

