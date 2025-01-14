clear
echo "Configuring Nvidia Gpu. Proceed (y/n)"

read choice;

if [ "$choice" != "y" ];then
   exit -1;
fi

yay -S nvidia-dkms
