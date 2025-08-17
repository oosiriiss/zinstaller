set -e

remove_repeating_whitespace() {
   x=$(echo "$1" | tr -s ' ')
   x=$(echo "$x" | sed -E "s/^ //g")
   x=$(echo "$x" | sed -E "s/ $//g")
   echo $x
}

# I think this step is done by default with new drivers on arch.
# But ill still do it just to make sure
echo "Explicitly setting modeset=1"
sudo echo "options nvidia_drm modeset=1" | sudo tee /etc/modprobe.d/nvidia.conf


MKINITCPIO_FILE="/etc/mkinitcpio.conf"
GRUB_CONFIG_FILE="etc/default/grub/"
MKINITCPIO_FILE="./test.txt"
GRUB_CONFIG_FILE="./test.txt"

echo "============================================================="
echo "Adding nvidia modules to MODULES array in $MKINITCPIO_FILE"
echo "============================================================="

TO_ADD=("nvidia"  "nvidia_modeset" "nvidia_uvm" "nvidia_drm")

modules_line=$(grep "^MODULES=" "$MKINITCPIO_FILE")

echo "The line look like this before: $modules_line"

existing_modules=$(echo "$modules_line" | sed -E 's/^MODULES=\((.*)\)/\1/')

echo "Existing modules: ${existing_modules[@]}"

for module in "${TO_ADD[@]}"; do
   if [[ ! " ${existing_modules[*]} " =~ " $module " ]]; then
      existing_modules+=("$module")
      echo "Adding module $module"
   else 
      echo "Module $module already exists"
   fi
done

# Using | instead of / in sed to avoid the need to replace '/'
echo "Loading i915 module before nvidia_packages"
echo "Deleting existing i915 module"
new_line=$(echo "$existing_modules" | sed -E "s|( ?)i915( ?)|\1|g")
echo "Line after deleting i915 $new_line"
echo "Appending i915 before first nvidia module"
new_line=$(echo "$new_line" | sed -E "s|([ \(])nvidia|\1i915 nvidia|")

echo "After appending modules: $new_line"

echo "Removing unnecessary spaces"
new_line=$(remove_repeating_whitespace "$new_line")
new_line="MODULES=($new_line)"
echo "Writing final line: $new_line to file"
sed -i "s|^MODULES=.*|$new_line|" $MKINITCPIO_FILE

echo ""
echo "============================================================="
echo "============================================================="
echo "============================================================="
echo ""
echo "Adding nvidia.NVreg_PreserveVideoMemoryAllocations=1 to grub kernel parameters. in $GRUB_CONFIG_FILE"
grub_line=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=.*" $GRUB_CONFIG_FILE)
echo "Grub kernel parameters line: $grub_line"
kernel_params=$(echo "$grub_line" | sed -E "s/.*\"(.*)\".*/\1/")
echo "Extracted parameters: $kernel_params"
echo "Removing nvidia.NVreg_PreserveVideoMemoryAllocations=1 if it exists (or is set to 0)"
kernel_params=$(echo "$kernel_params" | sed -E "s/( ?)nvidia\.NVreg_PreserveVideoMemoryAllocations=([01])( ?)/\1/")
echo "After removing param: $kernel_params"
echo "Appending the parameter."
kernel_params="$kernel_params nvidia.NVreg_PreserveVideoMemoryAllocations=1"
echo "Final parameters: $kernel_params"
echo "Removing unnecessary spaces"
kernel_params=$(remove_repeating_whitespace "$kernel_params")
echo "Final parameters: $kernel_params"
sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$kernel_params\"/" $GRUB_CONFIG_FILE
echo "wrote."


echo ""
echo "============================================================="
echo "============================================================="
echo "============================================================="
echo ""
echo "Rebuilidng grub config"
sudo grub-mkconfig -o /boot/grub/grub.cfg
echo "Rebuilding initcpio"
sudo mkinitcpio -P
# TODO :: possible redundant recreation of grub config?
#

