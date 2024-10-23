

# checking if ran as root
if [ "$EUID" -eq 0 ]; then
   echo "Dont run as root"
   exit 0;
fi

################################################## VARIABLES/CONSTANTS

USER=$(whoami)
USER_HOME="/home/$USER"

choice=false

echo "user home is: " $USER_HOME
echo "oosiriiss' Arch config install script"
echo "Prerequisites: "
echo "	1. git (signed in)"
echo "	2. run as user not root"
echo "	3. yay installed"


clear

################################################### Pacman sync

echo "Do you want to perform pacman sync? (y/n)"
read choice;

if [ "$choice" = "y" ]; then
   echo "Performing pacmna sync"
   sudo pacman -Syu
fi

clear

################################################### INSTALLIGN PACKAGES

source nvidia.sh

source terminal.sh

source login_manager.sh

source neovim.sh

source laptop_utils.sh

source neovim.sh

source nosetuppackages.sh

source laptop_utils.sh

source audio.sh

source terminal.sh

source hyprland.sh

source powertop.sh


################################################## Copying dotfiles

echo ""
echo ""
echo ""
echo "Downloading finished... Copying dotfiles to .config"
echo ""
echo ""
echo ""

USR_CFG_DIR=$(echo "$HOME/.config")

cp -r ../* "$USR_CFG_DIR/"
