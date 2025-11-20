#!/bin/bash
# ==============================================================================
#  ⚡ BAZZITE POWER SUITE - Main Hub
#  A modular TUI manager for Bazzite handhelds.
# ==============================================================================

# --- 1. Setup Paths ---
# Get the directory where this script is located
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_DIR/bin"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
GUM_BINARY="$BIN_DIR/gum"

# --- 2. Dependency Check: 'gum' ---
# We check for a local copy first, then a system copy.
# If neither exists, we download a standalone binary locally.

if [ -f "$GUM_BINARY" ]; then
    GUM="$GUM_BINARY"
elif command -v gum &> /dev/null; then
    GUM="gum"
else
    echo "--------------------------------------------------------"
    echo "❌ 'gum' (TUI engine) is required but was not found."
    echo "⚙️  Downloading standalone binary to $BIN_DIR..."
    echo "   (This does NOT require root or a reboot)"
    echo "--------------------------------------------------------"
    
    mkdir -p "$BIN_DIR"
    
    # Detect Architecture
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"
    elif [ "$ARCH" == "aarch64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_arm64.tar.gz"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    
    # Download and Extract
    if command -v curl &> /dev/null; then
        curl -L -o "$BIN_DIR/gum.tar.gz" "$URL"
    elif command -v wget &> /dev/null; then
        wget -O "$BIN_DIR/gum.tar.gz" "$URL"
    else
        echo "❌ Error: Neither 'curl' nor 'wget' found. Cannot download gum."
        exit 1
    fi

    tar -xzf "$BIN_DIR/gum.tar.gz" -C "$BIN_DIR"
    
    # Move binary to bin root and cleanup
    find "$BIN_DIR" -name "gum" -type f -exec mv {} "$BIN_DIR/" \;
    rm -rf "$BIN_DIR"/gum_* "$BIN_DIR/gum.tar.gz"
    chmod +x "$GUM_BINARY"
    
    GUM="$GUM_BINARY"
    echo "✅ 'gum' installed successfully."
    sleep 1
fi

# --- 3. Main Menu Function ---
show_main_menu() {
    clear
    
    # Display Header
    $GUM style \
        --border double \
        --margin "1" \
        --padding "1" \
        --border-foreground 212 \
        --foreground 212 \
        "⚡ BAZZITE POWER SUITE v1.0 ⚡" \
        "   [ Hub & Spoke Manager ]"

    # Render Menu
    # Add new tools to this list as you build them
    CHOICE=$($GUM choose \
        "🎥  Boot & Sleep Video Swapper (P10)" \
        "⚔️  Destiny Rising Helper (P24)" \
        "EXIT")

    # Handle Selection
    case "$CHOICE" in
        "🎥  Boot & Sleep Video Swapper (P10)")
            if [ -f "$SCRIPTS_DIR/video_swapper.sh" ]; then
                bash "$SCRIPTS_DIR/video_swapper.sh" "$GUM"
            else
                $GUM style --foreground 196 "❌ Error: Script 'scripts/video_swapper.sh' not found!"
                sleep 2
            fi
            ;;
            
        "⚔️  Destiny Rising Helper (P24)")
             if [ -f "$SCRIPTS_DIR/destiny_rising.sh" ]; then
                bash "$SCRIPTS_DIR/destiny_rising.sh" "$GUM"
            else
                $GUM style --foreground 196 "❌ Error: Script 'scripts/destiny_rising.sh' not found!"
                sleep 2
            fi
            ;;
            
        "EXIT")
            echo "Goodbye!"
            exit 0
            ;;
    esac
    
    # Return to menu after script finishes
    show_main_menu
}

# --- 4. Start the App ---
show_main_menu
```json
