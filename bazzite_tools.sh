#!/bin/bash
# ... (Keep your existing install_dir and gum checks at the top) ...

# --- DYNAMIC MODULE SCANNER ---
# 1. Declare a dictionary to map "Menu Titles" -> "File Paths"
declare -A SCRIPT_MAP

scan_scripts() {
    # Clear the map to avoid duplicates
    SCRIPT_MAP=()
    
    # Loop through every .sh file in the scripts folder
    for script in "$SCRIPTS_DIR"/*.sh; do
        [ -e "$script" ] || continue  # Safety check if folder is empty
        
        # Read the second line of the file (where we put the Title)
        # We look for a line starting with "# P" to identify it's a valid module
        HEADER=$(sed -n '2p' "$script")
        
        # If the line starts with "# P", clean it up to make it pretty
        if [[ "$HEADER" == "# P"* ]]; then
            # Remove the leading "# " hash and space
            TITLE="${HEADER:2}"
            
            # Map the Title to the File Path
            SCRIPT_MAP["$TITLE"]="$script"
        fi
    done
}

# --- Main Menu ---
show_main_menu() {
    scan_scripts
    
    clear
    $GUM style --border double --margin "1" --padding "1" --border-foreground 212 --foreground 212 "⚡ BAZZITE POWER SUITE ⚡" "   [ Auto-Discovery Hub ]"

    # 1. Extract the Titles (Keys) from our map
    # 2. Add an EXIT option manually
    # 3. Pass everything to gum choose
    CHOICE=$($GUM choose "${!SCRIPT_MAP[@]}" "EXIT")

    if [ "$CHOICE" == "EXIT" ]; then
        echo "Goodbye!"
        exit 0
    elif [ -n "$CHOICE" ]; then
        # Look up the file path using the chosen Title
        TARGET_SCRIPT="${SCRIPT_MAP[$CHOICE]}"
        
        if [ -f "$TARGET_SCRIPT" ]; then
            bash "$TARGET_SCRIPT" "$GUM"
        else
            echo "❌ Error: Could not launch $CHOICE"
            sleep 2
        fi
    fi
    
    show_main_menu
}

show_main_menu
