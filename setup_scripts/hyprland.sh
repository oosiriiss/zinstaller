clear

echo "Installing hyprland. Proceed(y/n)"
read choice;
if  [ "$choice" != "y" ]; then
   exit -1;
fi

echo "Downloading hyprland-git version"
yay -S  hyprland-git

echo "Downloading qt-libraries wayland support"
yay -S qt5-wayland qt6-wayland


echo "Do you have a Nvidia GPU? (y/n)"
read choice;


if [ "$choice" = "y" ]; then
   echo "Downloading egl-wayland for support with Nvidia"
   yay -S egl-wayland


   echo "Do you use GRUB bootloader? (y/n)"
   read choice;

   if [ "$choice" = "y" ]; then

      ############################## GRUB KENREL PARAMTERES ###################################

      LINE_NUMBER=$(grep -n "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | gawk '{print $1}' FS=":")
      LINE=$(grep -n "GRUB_CMDLINE_LINUX_DEFAULT" /etc/default/grub | gawk '{print $2}' FS=":")

      #making sure nvidia_drm.modeset=1 is not in the string
      LINE=$(echo "$LINE" | sed "s/nvidia_drm\.modeset=1//g")

      # removing last " sign
      LINE="${LINE::-1} nvidia_drm.modeset=1\""

      # Removing repeating spaces
      LINE=$( echo "$LINE" | tr -s ' ')

      # Replacing the line (adding nvidia_drm.modeset=1 to the grub)
      sudo sed -i "${LINE_NUMBER}s/^.*$/${LINE}/" /etc/default/grub     


      # Regenerating grub config
      sudo grub-mkconfig -o /boot/grub/grub.cfg    
   fi


   ############################## MKINITCPIO MODULES #######################################

      LINE_NUMBER=$(grep -n   "^MODULES" /etc/mkinitcpio.conf | gawk '{print $1}' FS=":")
      LINE=$(grep -n "^MODULES"  /etc/mkinitcpio.conf | gawk '{print $2}' FS=":")

      if [ "$LINE" = "" ];then
	 echo "Couldn't find MODULES in mkinitcpio.conf"
	 exit -1
      fi

      #removing duplicates
      LINE=$(echo "$LINE" | sed "s/nvidia_modeset//g")
      LINE=$(echo "$LINE" | sed "s/nvidia_uvm//g")
      LINE=$(echo "$LINE" | sed "s/nvidia_drm//g")
      LINE=$(echo "$LINE" | sed "s/ nvidia / /g")

      # removing last " sign and adding modules
      LINE="${LINE::-1} nvidia nvidia_modeset nvidia_uvm nvidia_drm )"

      # Removing repeating spaces
      LINE=$( echo "$LINE" | tr -s ' ')

      # Replacing the line in 
      sudo sed -i "${LINE_NUMBER}s/^.*$/${LINE}/" /etc/mkinitcpio.conf


      #Regenerating initcpio

      sudo mkinitcpio -P


      ################################## HYPRLAND ENV VARS ##########################


   ENV_FILE=$( echo "../hypr/env.conf")
   
   add_env() {
   
      # $1 - name
      # $2 - value
   
      # Removing duplicates
   
      sed_str="/env = $1.*/d"
      sed -i "$sed_str" $ENV_FILE
      
      echo "env = $1,$2" >> $ENV_FILE
   
   }
   
   echo "############################### NVIDIA ENV VARS ####################" >> $ENV_FILE

   add_env LIBVA_DRIVER_NAME nvidia
   add_env XDG_SESSION_TYPE wayland 
   add_env GBM_BACKEND nvidia-drm 
   add_env __GLX_VENDOR_LIBRARY_NAME nvidia

fi
##############################################################################
##############################     UI     ####################################
##############################################################################

echo "Downloading ttf-nerd-fonts-symbols (icons)"
yay -S ttf-nerd-fonts-symbols
echo "Downloading waybar (topbar)"
yay -S waybar

echo "Downloading hyprpaper (wallpapers for hyprland)"
yay -S hyprpaper

echo "Downloading rofi-lbonn-wayland-git (rofi with wayland)"
yay -S rofi-lbonn-wayland-git

echo "Downloading wlr-randr"
yay -S wlr-randr

echo "Downloading swaync"
yay -S swaync

echo "Downloading brightnessctl"
yay -S brightnessctl

echo "Downloading nautilus (file manager)"
yay -S nautilus 
