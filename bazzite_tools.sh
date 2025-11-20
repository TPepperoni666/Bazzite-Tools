#!/bin/bash
# Bazzite Power-Suite: Main Hub
# This script ensures dependencies are met and launches the TUI.

# --- Configuration ---
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_DIR/bin"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
GUM_BINARY="$BIN_DIR/gum"

# --- Dependency Check: GUM ---
# We check for a local copy first, then a system copy.
if [ -f "$GUM_BINARY" ]; then
    GUM="$GUM_BINARY"
elif command -v gum &> /dev/null; then
    GUM="gum"
else
    echo "❌ 'gum' is required for the interface but was not found."
    echo "⚙️  Downloading standalone 'gum' binary to $BIN_DIR..."

    mkdir -p "$BIN_DIR"
    # Detect Architecture (x86_64 or arm64)
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"
    elif [ "$ARCH" == "aarch64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_arm64.tar.gz"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi

    curl -L -o "$BIN_DIR/gum.tar.gz" "$URL"
    tar -xzf "$BIN_DIR/gum.tar.gz" -C "$BIN_DIR"
    mv "$BIN_DIR"/gum_*/gum "$BIN_DIR/"
    rm -rf "$BIN_DIR"/gum_* "$BIN_DIR/gum.tar.gz"

    GUM="$GUM_BINARY"
    echo "✅ 'gum' installed successfully."
    sleep 1
fi

# --- Main Menu Function ---
show_main_menu() {
    clear
    $GUM style \
        --border double \
        --margin "1" \
        --padding "1" \
        --border-foreground 212 \
        "⚡ BAZZITE POWER SUITE v1.0 ⚡" \
        "   [ Hub & Spoke Manager ]"

    CHOICE=$($GUM choose \
        "🎥  Boot & Sleep Video Swapper (P10)" \
        "⚔️  Destiny Rising Helper (P24)" \
        "EXIT")

    case "$CHOICE" in
        "🎥  Boot & Sleep Video Swapper (P10)")
            # Launch P10 Script
            if [ -f "$SCRIPTS_DIR/video_swapper.sh" ]; then
                bash "$SCRIPTS_DIR/video_swapper.sh" "$GUM"
            else
                $GUM style --foreground 196 "❌ Error: Script not found!"
                sleep 2
            fi
            ;;
        "⚔️  Destiny Rising Helper (P24)")
             if [ -f "$SCRIPTS_DIR/destiny_rising.sh" ]; then
                bash "$SCRIPTS_DIR/destiny_rising.sh" "$GUM"
            else
                $GUM style --foreground 196 "❌ Error: Script not found!"
                sleep 2
            fi
            ;;
        "EXIT")
            echo "Goodbye!"
            exit 0
            ;;
    esac

    # Loop back to menu after script finishes
    show_main_menu
}

# --- Start ---
show_main_menu
