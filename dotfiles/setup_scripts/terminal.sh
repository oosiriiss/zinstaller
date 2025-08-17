source ask_install_package.sh

TERMINAL="alacritty"

echo "Using $TERMINAL as the terminal emulator"

ask_install_package $TERMINAL

echo "Downloading zsh..."
yay -S zsh zsh-completions

echo "Chaning shell to zsh"
chsh -s /bin/zsh

ln ../.zshrc $HOME/

######################################## Add alacritty config here
