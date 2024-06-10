
source ask_install_package

NEOVIM_CONFIG_URL="https://github.com/oosiriiss/nvim-config"
ask_install_package neovim

echo "INSTALLING skarkdp/fd and ripgrep and wl-clipboard"
sudo pacman -S fd ripgrep wl-clipboard

echo "Do you want to clone neovim config from git (y/n)"
read choice;
if [ "$choice" = "y" ]; then
   while true; do
      echo "is this the right repository? url: $NEOVIM_CONFIG_URL (y/n)"
      read choice;
      if [ "$choice" = "y" ]; then
	 echo "Pulling neovim config to $USER_HOME/.config"
	 if  ! [[ -d "$USER_HOME/.config" ]] ;then
	 	mkdir "$USER_HOME/.config"
	 fi
	 if [[ -d "$USER_HOME/.config/nvim" ]];then
		 echo "Neovim config directory already exists do you want to override it? (y/n)"
		 read choice;
		 if [ "$choice" = "y" ];then
			 rm -rf "$USER_HOME/.config/nvim"
		else
			echo "Aborting download"
			break;
		fi
	fi
	 echo "Pulling..."
	 git clone $NEOVIM_CONFIG_URL "$USER_HOME/.config/nvim"
	 break;
      else
	 echo "Enter proper neovim config url or leave blank and press enter to abort"
	 read NEOVIM_CONFIG_URL;
	 if [ "$NEOVIM_CONFIG_URL" = "" ];then
	    break;
	 fi
      fi
   done
fi
