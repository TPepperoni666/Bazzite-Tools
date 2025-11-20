#!/bin/bash
# P24: Destiny Rising Waydroid Installer/Uninstaller
# Automates the setup, device spoofing, and controller fixes for Destiny Rising.

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

# Common package name for Destiny Rising (NetEase). 
# NOTE: Adjust this if the specific APK version uses a different ID.
PKG_NAME="com.netease.dne" 
APP_NAME="Destiny Rising"

install_destiny() {
    $GUM style --foreground 212 "⚙️  Starting Destiny Rising Setup..."

    # 1. Check for Waydroid
    if ! command -v waydroid &> /dev/null; then
        $GUM style --foreground 196 "❌ Waydroid is not installed!"
        echo "Please run 'ujust setup-waydroid' in Bazzite first."
        read -p "Press Enter to exit."
        return
    fi

    # 2. Check for ARM Translation (libhoudini)
    if [ ! -f "/var/lib/waydroid/overlay/system/lib64/libhoudini.so" ]; then
        $GUM style --foreground 226 "⚠️  ARM Translation (libhoudini) not detected."
        echo "Destiny Rising requires ARM translation."
        if $GUM confirm "Would you like to run the Waydroid Extras script to install it?"; then
             # Launching Bazzite's native helper
             ujust configure-waydroid
        else
             echo "Skipping. The game may not crash without libhoudini."
        fi
    fi

    # 3. Apply Fixes (Device Spoofing & Controller)
    $GUM style --foreground 120 "🔧 Applying Pixel 5 Spoof & Controller Fixes..."
    
    # Spoof as Pixel 5 (Redfin) to bypass "Device Not Supported"
    sudo waydroid prop set ro.product.model "Pixel 5"
    sudo waydroid prop set ro.product.name "redfin"
    sudo waydroid prop set ro.product.device "redfin"
    
    # Enable Controller Support (Pass-through udev events)
    sudo waydroid prop set persist.waydroid.udev true
    sudo waydroid prop set persist.waydroid.uevent true
    
    echo "✅ Props set."

    # 4. Install APK
    $GUM style --foreground 212 "📦  Install APK"
    echo "Please select your Destiny Rising APK file."
    
    APK_PATH=$($GUM file "$HOME/Downloads")
    
    if [ -n "$APK_PATH" ]; then
        echo "Installing $APK_PATH..."
        waydroid app install "$APK_PATH"
        $GUM style --foreground 120 "✅ Installation Complete!"
    else
        echo "❌ No file selected. Skipping APK install."
    fi
    
    # 5. Restart Session
    $GUM style --foreground 212 "🔄 Restarting Waydroid Session to apply fixes..."
    waydroid session stop
    sleep 2
    echo "Done. You can launch Destiny Rising from your menu."
    sleep 3
}

uninstall_destiny() {
    $GUM style --foreground 196 "🗑️  Uninstalling Destiny Rising..."
    
    # 1. Remove App
    if waydroid app list | grep -q "$PKG_NAME"; then
        waydroid app remove "$PKG_NAME"
        echo "✅ App removed."
    else
        echo "⚠️  App package ($PKG_NAME) not found. It may already be uninstalled."
    fi

    # 2. Optional: Revert Props
    if $GUM confirm "Do you want to revert the Pixel 5 Device Spoofing?"; then
        # Resetting to default Waydroid values (generic)
        sudo waydroid prop set ro.product.model "Waydroid x86_64"
        # Disable controller udev pass-through if desired (optional)
        # sudo waydroid prop set persist.waydroid.udev false
        echo "✅ Device props reverted."
    fi
    
    $GUM style --foreground 120 "✅ Uninstall Complete."
    sleep 2
}

# --- Sub-Menu ---
CHOICE=$($GUM choose "Install Destiny Rising (Apply Fixes + APK)" "Uninstall Destiny Rising" "Cancel")

case "$CHOICE" in
    "Install Destiny Rising"*)
        install_destiny
        ;;
    "Uninstall Destiny Rising")
        uninstall_destiny
        ;;
    *)
        exit 0
        ;;
esac
