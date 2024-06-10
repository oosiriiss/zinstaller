
ask_install_package() {
   # $1 - name of the installed package
   echo "Do you want  to download $1? (y/n)"
   read choice;
   if [ "$choice" = "y" ];then
      echo "Downloading $1"
      sudo pacman -S $1
      echo "$1 Download finished"
   fi
}
