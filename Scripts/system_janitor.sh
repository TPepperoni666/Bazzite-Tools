#!/bin/bash
# P2: Prefix and Shader Cleaner
# Scans and cleans Steam Shader Cache and CompatData (Prefixes).
# Features: Size Scan, Stale Data Scan, and Granular Deletion.

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

STEAM_HOME="$HOME/.local/share/Steam"
SHADER_DIR="$STEAM_HOME/steamapps/shadercache"
COMPAT_DIR="$STEAM_HOME/steamapps/compatdata"

# --- Helper: Convert Bytes to Human Readable ---
format_size() {
    numfmt --to=iec-i --suffix=B "$1"
}

# --- Helper: Delete Logic ---
perform_delete() {
    APPID=$1
    
    SHADER_PATH="$SHADER_DIR/$APPID"
    COMPAT_PATH="$COMPAT_DIR/$APPID"
    
    # Check existence
    HAS_SHADER=false
    HAS_COMPAT=false
    [ -d "$SHADER_PATH" ] && HAS_SHADER=true
    [ -d "$COMPAT_PATH" ] && HAS_COMPAT=true

    OPTIONS=()
    if $HAS_SHADER; then OPTIONS+=("Delete Shader Cache"); fi
    if $HAS_COMPAT; then OPTIONS+=("Delete Prefix (Saves/Config)"); fi
    if $HAS_SHADER && $HAS_COMPAT; then OPTIONS+=("NUKE BOTH (Delete Everything)"); fi
    OPTIONS+=("CANCEL")

    ACTION=$($GUM choose --header "Actions for AppID: $APPID" "${OPTIONS[@]}")

    case "$ACTION" in
        "Delete Shader Cache")
            rm -rf "$SHADER_PATH"
            $GUM style --foreground 120 "Shaders deleted." ;;
        "Delete Prefix"*)
            $GUM style --foreground 196 "WARNING: This deletes SAVES for AppID $APPID."
            if $GUM confirm "Are you sure?"; then
                rm -rf "$COMPAT_PATH"
                $GUM style --foreground 120 "Prefix deleted."
            fi ;;
        "NUKE BOTH"*)
            $GUM style --foreground 196 "DANGER: DELETING DATA AND SAVES FOR $APPID"
            if $GUM confirm "Are you absolutely sure?"; then
                rm -rf "$SHADER_PATH"
                rm -rf "$COMPAT_PATH"
                $GUM style --foreground 120 "All data nuked."
            fi ;;
        *) return ;;
    esac
    sleep 1
}

# --- Feature 1: Size Scan (The Hogs) ---
scan_hogs() {
    $GUM style --foreground 212 "Scanning for largest storage hogs..."
    
    TEMP_LIST="/tmp/janitor_hogs.txt"
    # Check CompatData sizes, sort descending, top 20
    du -s "$COMPAT_DIR"/* 2>/dev/null | sort -nr | head -n 20 > "$TEMP_LIST"

    if [ ! -s "$TEMP_LIST" ]; then
        $GUM style --foreground 196 "No data found."
        return
    fi

    declare -a MENU_ITEMS
    declare -A ID_MAP
    
    while read -r line; do
        SIZE_RAW=$(echo "$line" | awk '{print $1}')
        PATH_RAW=$(echo "$line" | awk '{print $2}')
        APPID=$(basename "$PATH_RAW")
        SIZE_HUMAN=$(format_size $((SIZE_RAW * 1024)))
        
        LABEL="ID: $APPID  |  Prefix Size: $SIZE_HUMAN"
        MENU_ITEMS+=("$LABEL")
        ID_MAP["$LABEL"]="$APPID"
    done < "$TEMP_LIST"

    CHOICE=$($GUM choose --header "Top 20 Largest Prefixes" "${MENU_ITEMS[@]}" "CANCEL")
    
    if [ "$CHOICE" != "CANCEL" ] && [ -n "$CHOICE" ]; then
        perform_delete "${ID_MAP[$CHOICE]}"
    fi
}

# --- Feature 2: Stale Scan (The Ghost Town) ---
scan_stale() {
    DAYS=90
    $GUM style --foreground 212 "Scanning for prefixes untouched for $DAYS+ days..."
    
    TEMP_LIST="/tmp/janitor_stale.txt"
    # Find directories in compatdata, modified more than 90 days ago
    find "$COMPAT_DIR" -maxdepth 1 -mindepth 1 -type d -mtime +$DAYS > "$TEMP_LIST"

    if [ ! -s "$TEMP_LIST" ]; then
        $GUM style --foreground 120 "No stale prefixes found! Clean ship."
        sleep 2
        return
    fi

    declare -a MENU_ITEMS
    declare -A ID_MAP
    
    while read -r PATH_RAW; do
        APPID=$(basename "$PATH_RAW")
        
        # Get exact date
        MOD_DATE=$(date -r "$PATH_RAW" "+%Y-%m-%d")
        
        # Get Size
        SIZE_RAW=$(du -s "$PATH_RAW" | awk '{print $1}')
        SIZE_HUMAN=$(format_size $((SIZE_RAW * 1024)))
        
        LABEL="ID: $APPID  |  Size: $SIZE_HUMAN  |  Last Used: $MOD_DATE"
        MENU_ITEMS+=("$LABEL")
        ID_MAP["$LABEL"]="$APPID"
    done < "$TEMP_LIST"

    CHOICE=$($GUM choose --header "Stale Prefixes (>3 Months)" "${MENU_ITEMS[@]}" "CANCEL")
    
    if [ "$CHOICE" != "CANCEL" ] && [ -n "$CHOICE" ]; then
        perform_delete "${ID_MAP[$CHOICE]}"
    fi
}

# --- Main Menu ---
show_janitor_menu() {
    clear
    $GUM style --border double --margin "1" --padding "1" --border-foreground 208 --foreground 208 "PREFIX & SHADER CLEANER" "   [ Free up Disk Space ]"

    CHOICE=$($GUM choose \
        "Find Storage Hogs (Sort by Size)" \
        "Find Stale Prefixes (Not used in 3 Months)" \
        "EXIT")

    case "$CHOICE" in
        "Find Storage Hogs"*) scan_hogs ;;
        "Find Stale Prefixes"*) scan_stale ;;
        "EXIT") return ;;
    esac
    
    show_janitor_menu
}

show_janitor_menu
