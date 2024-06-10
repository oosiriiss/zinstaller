
   ENV_FILE=$( echo "$HOME/.config/hypr/hyprland.conf")
   

   add_env() {
   
      # $1 - name
      # $2 - value
   
      # Removing duplicates
   
      sed_str="/env = $1.*/d"
      sed -i "$sed_str" $ENV_FILE
      
      echo "env = $1,$2" >> $ENV_FILE
   
   }
   
   add_env LIBVA_DRIVER_NAME nvidia
   add_env XDG_SESSION_TYPE wayland 
   add_env GBM_BACKEND nvidia-drm 
   add_env __GLX_VENDOR_LIBRARY_NAME nvidia



