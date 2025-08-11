# $CONFIG_DIR_PATH is envvar set by the installer

NEOVIM_CONFIG_URL="https://github.com/oosiriiss/nvim-config"
NEOVIM_TARGET_DIR="$CONFIG_DIR_PATH/nvim"

echo "Cloning neovim config from repository: $NEOVIM_CONFIG_URL to local directory: $NEOVIM_TARGET_DIR";

if [[ -d "$NEOVIM_TARGET_DIR" ]]; then
   echo "Neovim config directory already exists. Overriding...";
   rm -rf "$NEOVIM_TARGET_DIR";
fi

git clone "$NEOVIM_CONFIG_URL" "$NEOVIM_TARGET_DIR"
