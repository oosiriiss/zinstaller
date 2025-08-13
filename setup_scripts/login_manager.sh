echo "Enabling sddm service"
sudo systemctl enable sddm

# Setting up the config
CONFIG_REPO_URL="http://github.com/oosiriiss/sddm-eclipse-theme"
CONFIG_REPO_DIR="eclipse"
# sddm config
BASE_SDDM_CONFIG_DIR="/etc/sddm.conf.d"
CONFIG_FILENAME="oosiriiss.conf"
TARGET_CONFIG_PATH="$BASE_SDDM_CONFIG_DIR/$CONFIG_FILENAME"
SDDM_DEFAULT_CONFIG_PATH="/usr/lib/sddm/sddm.conf.d/default.conf"

# sddm Themes dir
BASE_SDDM_THEMES_DIR="/usr/share/sddm/themes/"
THEME_NAME="eclipse"

# In case a directory with given name already exists which would conflict with git clone :)
if [ -d "$CONFIG_REPO_DIR" ]; then
   echo "found directory $CONFIG_REPO_DIR in current directory."
   CONFIG_REPO_DIR="${CONFIG_REPO_DIR}_REALLY_FROM_SETUP_SCRIPT"
   echo "Changed it to $CONFIG_REPO_DIR"
   if [ -d "$CONFIG_REPO_DIR" ]; then
      echo "Directory $CONFIG_REPO_DIR still exists. I hope it was created during previous attempt of running this script (and it failed), because it will be now deleted :)"
      rm -rf $CONFIG_REPO_DIR
   fi
fi

echo "Cloning sddm config repostiory from $CONFIG_REPO_URL";
git clone $CONFIG_REPO_URL $CONFIG_REPO_DIR

echo "Copying $THEME_NAME theme to sddm theme directory at $BASE_SDDM_THEMES_DIR"
sudo cp -r $CONFIG_REPO_DIR "$BASE_SDDM_THEMES_DIR/$THEME_NAME"

if ! [ -d "$BASE_SDDM_CONFIG_DIR" ]; then
   echo "sddm config directory didn't exist - creating it".;
   sudo mkdir -p "$BASE_SDDM_CONFIG_DIR"
fi

if [ -f "$TARGET_CONFIG_PATH" ]; then
   echo "Found config file at path $TARGET_CONFIG_PATH"
else
   echo "Config file not found. Copying the default config from  to path $TARGET_CONFIG_PATH"
   sudo cp "$SDDM_DEFAULT_CONFIG_PATH" "$TARGET_CONFIG_PATH"
fi

echo "Setting the theme in config file $TARGET_CONFIG_PATH"
sudo sed -i "s/^Current=.*/Current=$THEME_NAME/" $TARGET_CONFIG_PATH

echo "Changing permissions to 777 for the eclipse.png background image"
sudo chmod 777 "$BASE_SDDM_THEMES_DIR/$THEME_NAME/images/eclipse.png"

echo "Deleting the cloned repository"
rm -rf $CONFIG_REPO_DIR
