#!/bin/bash

# USB-Soft-KVM Installation Script
# This script configures udev rules to automatically switch monitor inputs
# when a USB keyboard is connected/disconnected

set -e

# Check for sudo permissions
if ! sudo -v; then
    echo "Error: This script requires sudo privileges."
    echo "Please run with sudo access or ensure you can use sudo."
    exit 1
fi

# Keep sudo alive throughout the script
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &

# Check if dialog is installed
if ! command -v dialog &> /dev/null; then
    echo "Installing dialog..."
    sudo apt-get update
    sudo apt-get install -y dialog
fi

# Check if ddccontrol is installed
if ! command -v ddccontrol &> /dev/null; then
    dialog --title "Missing Dependency" --yesno "ddccontrol is not installed. Install it now?" 10 50
    if [ $? -eq 0 ]; then
        sudo apt-get update
        sudo apt-get install -y ddccontrol
    else
        dialog --title "Error" --msgbox "ddccontrol is required. Installation aborted." 8 50
        clear
        exit 1
    fi
fi

clear

# Main menu
ACTION=$(dialog --title "USB-Soft-KVM" --menu "Choose an action:" 12 60 2 \
    "1" "Install or Reinstall" \
    "2" "Uninstall" \
    3>&1 1>&2 2>&3)

if [ -z "$ACTION" ]; then
    clear
    exit 0
fi

if [ "$ACTION" = "2" ]; then
    # Uninstall
    dialog --title "USB-Soft-KVM Uninstaller" --yesno "This will remove USB-Soft-KVM from your system.\n\nContinue?" 10 50
    if [ $? -ne 0 ]; then
        clear
        exit 0
    fi
    
    echo "Uninstalling USB-Soft-KVM..."
    
    # Remove udev rules
    UDEV_RULES="/etc/udev/rules.d/90-usb-soft-kvm.rules"
    if [ -f "$UDEV_RULES" ]; then
        echo "Removing udev rules..."
        sudo rm -f "$UDEV_RULES"
    fi
    
    # Reload udev rules
    echo "Reloading udev rules..."
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    
    dialog --title "Uninstallation Complete" --msgbox "USB-Soft-KVM has been removed from your system." 8 50
    clear
    echo "Uninstallation complete!"
    echo "All USB-Soft-KVM components have been removed."
    exit 0
fi

# Welcome message for installation
dialog --title "USB-Soft-KVM Installer" --msgbox "This installer will help you configure automatic monitor input switching based on USB keyboard connection.\n\nYou will need to:\n1. Identify your I2C bus\n2. Identify input source values\n3. Identify your keyboard" 15 60

# Step 1: Identify I2C Bus
dialog --title "Step 1: I2C Bus Detection" --msgbox "Running ddccontrol to detect monitors...\n\nPress OK to continue." 10 50

# Run ddccontrol and capture output
DDCCONTROL_OUTPUT=$(sudo ddccontrol -p 2>&1)

# Extract I2C devices
I2C_DEVICES=$(echo "$DDCCONTROL_OUTPUT" | grep -oP "dev:/dev/i2c-\d+" | sort -u)

if [ -z "$I2C_DEVICES" ]; then
    dialog --title "Error" --msgbox "No DDC/CI capable monitors found!\n\nMake sure:\n- Your monitor supports DDC/CI\n- i2c-dev module is loaded\n- You have proper permissions" 12 60
    clear
    exit 1
fi

# Create menu options for I2C devices
I2C_MENU=()
while IFS= read -r device; do
    # Try to get monitor name
    MONITOR_INFO=$(echo "$DDCCONTROL_OUTPUT" | grep -A 2 "$device" | grep "Monitor Name" | cut -d: -f2 | xargs || echo "Unknown Monitor")
    I2C_MENU+=("$device" "$MONITOR_INFO")
done <<< "$I2C_DEVICES"

DEVICE=$(dialog --title "Select I2C Bus" --menu "Choose your monitor's I2C bus:" 15 70 5 "${I2C_MENU[@]}" 3>&1 1>&2 2>&3)

if [ -z "$DEVICE" ]; then
    clear
    exit 1
fi

# Extract just the device path
DEVICE_PATH=$(echo "$DEVICE" | grep -oP "/dev/i2c-\d+")

dialog --title "I2C Bus Selected" --msgbox "Selected device: $DEVICE_PATH" 8 50

# Step 2: Identify Input Source Values
dialog --title "Step 2: Input Source Values" --msgbox "Now we need to identify the input source values.\n\nThe available inputs with their values (e.g., HDMI-1: 17, DP-1: 15) will be detected automatically.\n\nPress OK to continue." 12 60

# Extract possible input values from the output
INPUT_VALUES=$(echo "$DDCCONTROL_OUTPUT" | sed -n '/Input settings/,/supported, value/p' | grep "value=" | grep -oP "value=\d+" | cut -d= -f2 | sort -u)

if [ -n "$INPUT_VALUES" ]; then
    # Create menu from detected values
    INPUT_MENU=()
    while IFS= read -r value; do
        INPUT_NAME=$(echo "$DDCCONTROL_OUTPUT" | grep "value=$value" | grep -oP "name=\K[^,]+" | head -1 || echo "Input $value")
        INPUT_MENU+=("$value" "$INPUT_NAME")
    done <<< "$INPUT_VALUES"
    
    INPUT_CONNECTED=$(dialog --title "Desktop Input (Connected)" --menu "Select the input value for your DESKTOP (when keyboard is connected):" 20 70 10 "${INPUT_MENU[@]}" 3>&1 1>&2 2>&3)
    
    if [ -z "$INPUT_CONNECTED" ]; then
        clear
        exit 1
    fi
    
    INPUT_DISCONNECTED=$(dialog --title "Laptop Input (Disconnected)" --menu "Select the input value for your LAPTOP (when keyboard is disconnected):" 20 70 10 "${INPUT_MENU[@]}" 3>&1 1>&2 2>&3)
    
    if [ -z "$INPUT_DISCONNECTED" ]; then
        clear
        exit 1
    fi
else
    # Manual input if we couldn't parse values
    INPUT_CONNECTED=$(dialog --title "Desktop Input Value" --inputbox "Enter the input value for your DESKTOP (e.g., 15 for DisplayPort):" 10 60 "16" 3>&1 1>&2 2>&3)
    INPUT_DISCONNECTED=$(dialog --title "Laptop Input Value" --inputbox "Enter the input value for your LAPTOP (e.g., 17 for HDMI):" 10 60 "17" 3>&1 1>&2 2>&3)
fi

# Step 3: Identify Keyboard
dialog --title "Step 3: Keyboard Detection" --msgbox "Next, we need to identify your USB keyboard.\n\nPlease make sure your USB keyboard is PLUGGED IN, then press OK." 10 60

# List USB devices
USB_DEVICES=$(lsusb)

# Try to detect keyboards
KEYBOARD_CANDIDATES=$(echo "$USB_DEVICES" | grep -i "keyboard\|hid" || true)

if [ -n "$KEYBOARD_CANDIDATES" ]; then
    KEYBOARD_MENU=()
    while IFS= read -r kbd; do
        # Extract vendor and product IDs
        VENDOR_PRODUCT=$(echo "$kbd" | grep -oP "ID \K[0-9a-f:]+")
        VENDOR_ID=$(echo "$VENDOR_PRODUCT" | cut -d: -f1)
        PRODUCT_ID=$(echo "$VENDOR_PRODUCT" | cut -d: -f2)
        # Extract name
        NAME=$(echo "$kbd" | cut -d: -f3- | xargs)
        KEYBOARD_MENU+=("$VENDOR_ID:$PRODUCT_ID" "$NAME")
    done <<< "$KEYBOARD_CANDIDATES"
    
    KEYBOARD_IDS=$(dialog --title "Select Keyboard" --menu "Choose your USB keyboard:" 20 80 10 "${KEYBOARD_MENU[@]}" 3>&1 1>&2 2>&3)
    
    if [ -z "$KEYBOARD_IDS" ]; then
        clear
        exit 1
    fi
    
    VENDOR_ID=$(echo "$KEYBOARD_IDS" | cut -d: -f1)
    PRODUCT_ID=$(echo "$KEYBOARD_IDS" | cut -d: -f2)
    
    # Get the keyboard name for lsusb matching
    KEYBOARD_NAME=$(echo "$USB_DEVICES" | grep "$VENDOR_ID:$PRODUCT_ID" | cut -d: -f3- | xargs)
else
    dialog --title "Error" --msgbox "No keyboards detected!\n\nMake sure your USB keyboard is plugged in." 8 50
    clear
    exit 1
fi

# Summary
dialog --title "Configuration Summary" --msgbox "Configuration Summary:\n\nI2C Device: $DEVICE_PATH\nDesktop Input: $INPUT_CONNECTED\nLaptop Input: $INPUT_DISCONNECTED\nKeyboard Vendor ID: $VENDOR_ID\nKeyboard Product ID: $PRODUCT_ID\nKeyboard Name: $KEYBOARD_NAME" 15 70

# Confirm installation
dialog --title "Confirm Installation" --yesno "Do you want to install the USB-Soft-KVM with these settings?" 8 50

if [ $? -ne 0 ]; then
    clear
    exit 0
fi

# Create udev rules with inline commands
UDEV_RULES="/etc/udev/rules.d/90-usb-soft-kvm.rules"
cat << EOF | sudo tee "$UDEV_RULES" > /dev/null
# USB-Soft-KVM - Automatic monitor input switching
# Generated by usb-soft-kvm.sh
ACTION=="add", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", RUN+="/bin/sh -c '/usr/bin/ddccontrol -r 0x60 -w $INPUT_CONNECTED dev:$DEVICE_PATH; /usr/bin/logger \"USB-Soft-KVM: Keyboard connected - switched to input $INPUT_CONNECTED (Desktop)\"'"
ACTION=="remove", ATTRS{idVendor}=="$VENDOR_ID", ATTRS{idProduct}=="$PRODUCT_ID", RUN+="/bin/sh -c '/usr/bin/ddccontrol -r 0x60 -w $INPUT_DISCONNECTED dev:$DEVICE_PATH; /usr/bin/logger \"USB-Soft-KVM: Keyboard disconnected - switched to input $INPUT_DISCONNECTED (Laptop)\"'"
EOF

# Reload udev rules
sudo udevadm control --reload-rules
sudo udevadm trigger

dialog --title "Installation Complete" --msgbox "USB-Soft-KVM has been installed successfully!\n\nThe system will now automatically switch your monitor input when you toggle your USB keyboard.\n\nTo test: Unplug and replug your USB keyboard.\n\nTo uninstall: Run this script again and select Uninstall." 14 60

clear
echo "Installation complete!"
echo ""
echo "Configuration:"
echo "  I2C Device: $DEVICE_PATH"
echo "  Desktop Input: $INPUT_CONNECTED"
echo "  Laptop Input: $INPUT_DISCONNECTED"
echo "  Keyboard: $KEYBOARD_NAME"
echo "  Udev Rules: $UDEV_RULES"
echo ""
echo "Test by unplugging and replugging your USB keyboard."
echo "Check logs with: journalctl -f | grep USB-Soft-KVM"
