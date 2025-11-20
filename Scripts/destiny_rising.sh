#!/bin/bash
# P24: Destiny Rising Waydroid Installer/Uninstaller
# Automates the setup, device spoofing, and controller fixes for Destiny Rising.
# Optimized for Bazzite & Legion Go.

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

# Constants
PKG_NAME="com.netease.g108na" # Play Store Package ID for Destiny Rising
APP_NAME="Destiny Rising"

# --- Helper Functions ---

# The "Deep Spoof" Identity Block (Pixel 5 Redfin + Legion Go Graphics)
get_identity_block() {
cat <<EOF
##########################################################################
### PIXEL 5 SPOOF (Destiny Rising Fix)
ro.product.brand=google
ro.product.manufacturer=google
ro.system.build.product=redfin
ro.product.name=redfin
ro.product.device=redfin
ro.product.model=Pixel 5
ro.system.build.flavor=redfin-user
ro.build.fingerprint=google/redfin/redfin:11/RQ3A.211001.001/eng.electr.20230318.111310:user/release-keys
ro.system.build.description=redfin-user 11 RQ3A.211001.001 eng.electr.20230318.111310 release-keys
ro.bootimage.build.fingerprint=google/redfin/redfin:11/RQ3A.211001.001/eng.electr.20230318.111310:user/release-keys
ro.build.display.id=google/redfin/redfin:11/RQ3A.211001.001/eng.electr.20230318.111310:user/release-keys
ro.build.tags=release-keys
ro.build.description=redfin-user 11 RQ3A.211001.001 eng.electr.20230318.111310 release-keys
ro.vendor.build.fingerprint=google/redfin/redfin:11/RQ3A.211001.001/eng.electr.20230318.111310:user/release-keys
ro.vendor.build.id=RQ3A.211001.001
ro.vendor.build.tags=release-keys
ro.vendor.build.type=user
ro.odm.build.tags=release-keys

### LEGION GO GRAPHICS FIX
ro.hardware.gralloc=minigbm_gbm_mesa
ro.hardware.vulkan=radeon
##########################################################################
EOF
}

apply_patch() {
    local file=$1
    if [ -f "$file" ]; then
        # Clean old keys to prevent duplicates
        KEYS=("ro.product.brand" "ro.product.manufacturer" "ro.system.build.product" "ro.product.name" "ro.product.device" "ro.product.model" "ro.system.build.flavor" "ro.build.fingerprint" "ro.system.build.description" "ro.bootimage.build.fingerprint" "ro.build.display.id" "ro.build.tags" "ro.build.description" "ro.vendor.build.fingerprint" "ro.vendor.build.id" "ro.vendor.build.tags" "ro.vendor.build.type" "ro.odm.build.tags" "ro.hardware.gralloc" "ro.hardware.vulkan")
        for key in "${KEYS[@]}"; do sudo sed -i "/^$key=/d" "$file"; done
        
        # Append block
        get_identity_block | sudo tee -a "$file" > /dev/null
    fi
}

# --- Main Actions ---

install_destiny() {
    $GUM style --foreground 212 "⚙️  Starting Destiny Rising Setup..."

    # 1. Check for Waydroid
    if ! command -v waydroid &> /dev/null; then
        $GUM style --foreground 196 "❌ Waydroid is not installed!"
        echo "Please run 'rpm-ostree install waydroid' in Bazzite and reboot first."
        read -p "Press Enter to exit."
        return
    fi

    # 2. Initialize if missing
    if [ ! -f "/var/lib/waydroid/images/system.img" ]; then
        $GUM style --foreground 226 "⚠️  Waydroid not initialized."
        if $GUM confirm "Download Android 13 (GApps)?"; then
             sudo waydroid init -s GAPPS -f -c https://ota.waydro.id/system -v https://ota.waydro.id/vendor
        else
             return
        fi
    fi

    # 3. Start Container
    sudo systemctl enable --now waydroid-container
    
    # 4. Check for ARM Translation (LibNDK for AMD / LibHoudini for Intel)
    # Assuming Legion Go/Deck (AMD) -> LibNDK
    if [ ! -d "/var/lib/waydroid/overlay/system/lib64/libndk_translation" ]; then
        $GUM style --foreground 226 "⚠️  ARM Translation (LibNDK) not detected."
        if $GUM confirm "Install LibNDK (Required for AMD Handhelds)?"; then
             WORKDIR="/tmp/wd_install"
             [ -d "$WORKDIR" ] && sudo rm -rf "$WORKDIR"
             git clone https://github.com/casualsnek/waydroid_script "$WORKDIR"
             cd "$WORKDIR"
             python3 -m venv venv
             venv/bin/pip install -r requirements.txt --upgrade
             sudo venv/bin/python3 main.py install libndk
             cd ~
        fi
    fi

    # 5. Apply Fixes (Deep Spoof + Graphics)
    $GUM style --foreground 120 "🔧 Applying Pixel 5 Spoof & Legion Go Fixes..."
    
    # Stop session to apply configs safely
    waydroid session stop > /dev/null 2>&1
    sudo systemctl stop waydroid-container
    sudo killall -9 waydroid-session 2>/dev/null

    # Apply Dual-File Patch
    apply_patch "/var/lib/waydroid/waydroid.prop"
    apply_patch "/var/lib/waydroid/waydroid_base.prop"
    
    # Enable UEvents (Controller)
    sudo waydroid prop set persist.waydroid.uevent true

    echo "✅ Configuration Patched."

    # 6. Setup Smart Launcher & Permissions
    $GUM style --foreground 212 "🚀 Setting up Smart Launcher..."
    
    # Create Controller Fix Script
    FIX_SCRIPT="/usr/local/bin/wd-fix-controllers"
    sudo bash -c "cat > $FIX_SCRIPT" <<EOL
#!/bin/bash
# Trigger uevents for input devices
for event in /sys/class/input/event*/uevent; do
    echo add > "\$event" 2>/dev/null
done
EOL
    sudo chmod +x $FIX_SCRIPT
    
    # Add sudoers rule for password-less fix in Game Mode
    echo "Adding permission rule..."
    sudo bash -c "echo '%wheel ALL=(ALL) NOPASSWD: $FIX_SCRIPT' > /etc/sudoers.d/wd-fix-controllers"

    # Create Launcher
    LAUNCHER="$HOME/.local/bin/launch_destiny.sh"
    mkdir -p "$(dirname "$LAUNCHER")"
    cat > "$LAUNCHER" <<EOL
#!/bin/bash
# Smart Launcher for Destiny: Rising
cleanup() { waydroid session stop; }
trap cleanup EXIT
waydroid session stop
sleep 2
waydroid session start &
sleep 8
sudo $FIX_SCRIPT
waydroid app launch $PKG_NAME
sleep infinity
EOL
    chmod +x "$LAUNCHER"

    # Create Shortcut
    SHORTCUT="$HOME/.local/share/applications/DestinyRising.desktop"
    mkdir -p "$(dirname "$SHORTCUT")"
    cat > "$SHORTCUT" <<EOL
[Desktop Entry]
Name=Destiny: Rising
Comment=Play Destiny: Rising via Waydroid (Smart Launcher)
Exec=$LAUNCHER
Icon=phone
Terminal=false
Type=Application
Categories=Game;
EOL
    chmod +x "$SHORTCUT"
    
    # 7. Copy to Visible Folder (For Steam)
    USER_DIR="$HOME/Waydroid_Launchers"
    mkdir -p "$USER_DIR"
    cp "$SHORTCUT" "$USER_DIR/"

    echo "✅ Launcher Created in $USER_DIR"
    
    # 8. Restart
    sudo systemctl start waydroid-container
    
    $GUM style --foreground 120 "✅ Setup Complete!"
    echo "1. Register Device ID (ujust setup-waydroid -> Configure -> Get ID)"
    echo "2. Install Destiny: Rising from Play Store (Recommended) OR select APK below."
    
    # 9. Optional APK Install
    if $GUM confirm "Do you have a Destiny Rising APK to install now?"; then
        APK_PATH=$($GUM file "$HOME/Downloads")
        if [ -n "$APK_PATH" ]; then
            echo "Installing $APK_PATH..."
            waydroid app install "$APK_PATH"
            $GUM style --foreground 120 "✅ APK Installed!"
        fi
    fi
    
    sleep 3
}

uninstall_destiny() {
    $GUM style --foreground 196 "🗑️  Uninstalling Destiny Rising Configs..."
    
    # 1. Remove Shortcut
    rm -f "$HOME/.local/share/applications/DestinyRising.desktop"
    rm -f "$HOME/.local/bin/launch_destiny.sh"
    rm -rf "$HOME/Waydroid_Launchers"
    
    # 2. Remove Sudoers Rule
    if [ -f "/etc/sudoers.d/wd-fix-controllers" ]; then
        echo "Removing permission rules..."
        sudo rm -f "/etc/sudoers.d/wd-fix-controllers"
        sudo rm -f "/usr/local/bin/wd-fix-controllers"
    fi

    # 3. Revert Props (Optional)
    if $GUM confirm "Do you want to revert the Pixel 5 & Graphics fix?"; then
        echo "Resetting Waydroid config..."
        waydroid session stop
        sudo systemctl stop waydroid-container
        sudo rm -f /var/lib/waydroid/waydroid.prop
        sudo waydroid upgrade --offline
        echo "✅ Device props reverted."
    fi
    
    $GUM style --foreground 120 "✅ Uninstall Complete."
    sleep 2
}

# --- Sub-Menu ---
CHOICE=$($GUM choose "Install Destiny Rising (Apply Fixes + Launcher)" "Uninstall Destiny Rising Tools" "Cancel")

case "$CHOICE" in
    "Install Destiny Rising"*)
        install_destiny
        ;;
    "Uninstall Destiny Rising"*)
        uninstall_destiny
        ;;
    *)
        exit 0
        ;;
esac
