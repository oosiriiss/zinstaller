
echo "Is this laptop with iGPU and dGPU (y/n)"
read choice;
if [ "$choice" != "y" ];then
   exit -1;
fi


echo ""
echo "Do you want to install asusctl and supergfxctl? (y/n)"

read choice;

if [ "$choice" != "y" ]; then
   exit -1;
fi

echo "Installing...."
echo ""

if ! command -v yay &> /dev/null;then
   echo "Yay is not installed on  this system. Cannot proceed"
   exit -1;
fi

yay -S asusctl supergfxctl

echo "Enable supergfxd service"
sudo systemctl enable supergfxd




echo ""
echo "Do you want to limit max battery charge to 80%? (y/n)"
read choice;

if [ "$choice" = "y" ];then
   asusctl --chg-limit 80
fi





