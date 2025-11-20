#!/bin/bash
# ==============================================================================
#  ⚡ BAZZITE POWER SUITE - Main Hub
#  A modular TUI manager for Bazzite handhelds.
# ==============================================================================

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$INSTALL_DIR/bin"
SCRIPTS_DIR="$INSTALL_DIR/scripts"
GUM_BINARY="$BIN_DIR/gum"

# --- Dependency Check: 'gum' ---
if [ -f "$GUM_BINARY" ]; then
    GUM="$GUM_BINARY"
elif command -v gum &> /dev/null; then
    GUM="gum"
else
    echo "--------------------------------------------------------"
    echo "❌ 'gum' (TUI engine) is required but was not found."
    echo "⚙️  Downloading standalone binary to $BIN_DIR..."
    mkdir -p "$BIN_DIR"
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"
    elif [ "$ARCH" == "aarch64" ]; then
        URL="https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_arm64.tar.gz"
    else
        echo "❌ Unsupported architecture: $ARCH"
        exit 1
    fi
    
    if command -v curl &> /dev/null; then curl -L -o "$BIN_DIR/gum.tar.gz" "$URL"
    elif command -v wget &> /dev/null; then wget -O "$BIN_DIR/gum.tar.gz" "$URL"
    else echo "❌ Error: Neither 'curl' nor 'wget' found."; exit 1; fi

    tar -xzf "$BIN_DIR/gum.tar.gz" -C "$BIN_DIR"
    find "$BIN_DIR" -name "gum" -type f -exec mv {} "$BIN_DIR/" \;
    rm -rf "$BIN_DIR"/gum_* "$BIN_DIR/gum.tar.gz"
    chmod +x "$GUM_BINARY"
    GUM="$GUM_BINARY"
    echo "✅ 'gum' installed successfully."
    sleep 1
fi

# --- DYNAMIC MODULE SCANNER ---
# Maps "Menu Title" -> "File Path"
declare -A SCRIPT_MAP

scan_scripts() {
    SCRIPT_MAP=()
    # Loop through every .sh file in scripts/
    for script in "$SCRIPTS_DIR"/*.sh; do
        [ -e "$script" ] || continue
        
        # Read Line 2
        HEADER=$(sed -n '2p' "$script")
        
        # Check if Line 2 starts with "# P" (our convention)
        if [[ "$HEADER" == "# P"* ]]; then
            # Strip the leading "# " (first 2 chars)
            TITLE="${HEADER:2}"
            SCRIPT_MAP["$TITLE"]="$script"
        fi
    done
}

# --- Main Menu ---
show_main_menu() {
    scan_scripts
    
    clear
    $GUM style --border double --margin "1" --padding "1" --border-foreground 212 --foreground 212 "⚡ BAZZITE POWER SUITE ⚡" "   [ Auto-Discovery Hub ]"

    # Sort keys alphabetically so P1, P2, P10 appear in order
    # We use printf to list keys, sort them, and store in array
    IFS=$'\n' read -d '' -r -a SORTED_OPTIONS < <(printf '%s\n' "${!SCRIPT_MAP[@]}" | sort && printf '\0')

    if [ ${#SORTED_OPTIONS[@]} -eq 0 ]; then
        $GUM style --foreground 196 "❌ No valid scripts found in /scripts!"
        $GUM style --foreground 240 "Tip: Ensure scripts have '# P...' on line 2."
        exit 1
    fi

    CHOICE=$($GUM choose "${SORTED_OPTIONS[@]}" "EXIT")

    if [ "$CHOICE" == "EXIT" ]; then
        echo "Goodbye!"
        exit 0
    elif [ -n "$CHOICE" ]; then
        TARGET_SCRIPT="${SCRIPT_MAP[$CHOICE]}"
        
        if [ -f "$TARGET_SCRIPT" ]; then
            # Pass the gum location to the child script
            bash "$TARGET_SCRIPT" "$GUM"
        else
            echo "❌ Error: Could not launch $CHOICE"
            sleep 2
        fi
    fi
    
    show_main_menu
}

show_main_menu
