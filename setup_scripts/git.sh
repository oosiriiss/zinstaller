set -e

NAME="oosiriiss"
EMAIL="oosiriiss@gmail.com"
EDITOR="nvim"

echo "Settings git user.name to $NAME"
git config --global user.name "$NAME"

echo "Setting git user.email to $EMAIL"
git config --global user.email "$EMAIL"

echo "Setting it core.editor to $EDITOR"
git config --global core.editor "$EDITOR"
