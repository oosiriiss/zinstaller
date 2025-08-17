set -e


sudo chsh -s /bin/zsh
# $ CONFIG_DIR should be set by the 
mv "$DOTFILES_DIR/.zshrc" "$HOME/"

