


source ask_install_package

LOGIN_MANAGER="sddm"


ask_install_package $LOGIN_MANAGER

Echo "Enabling sddm service"
sudo systemctl enable sddm

############################################## Add login manager config
