#!/bin/bash
# P1: Cloud Save Wrapper (GBM Integrated) ☁️
# - Reads Backup Schedule from Game Backup Manager
# - Scrapes PCGamingWiki for paths
# - Auto-Configures Syncthing

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

# --- Dependencies ---
if ! command -v jq &> /dev/null; then echo "Installing jq..." && rpm-ostree install jq --apply-live; fi

# --- INTEGRATION PATHS (Matches your GBM Script) ---
GBM_SCRIPTS_DIR="$HOME/scripts"
GBM_SERVICE_FILE="$HOME/.config/systemd/user/bazzite-prefix-backup.service"
GBM_LOOKUP_FILE="$GBM_SCRIPTS_DIR/non_steam_games.csv"
GBM_MAP_FILE="$GBM_SCRIPTS_DIR/save_sync_map.csv"

# --- Cloud Config ---
CLOUD_CONFIG="$HOME/.config/bazzite_cloud.conf"
SYNCTHING_CONFIG="$HOME/.config/syncthing/config.xml"
SYNCTHING_URL="http://localhost:8384"
API_KEY=""

# --- 1. Storage Setup ---
setup_storage() {
    # Set Hub Path to ~/Cloud Saves
    HUB_PATH="$HOME/Cloud Saves"
    mkdir -p "$HUB_PATH"
    echo "$HUB_PATH" > "$CLOUD_CONFIG"

    # Syncthing Hook
    if [ -f "$SYNCTHING_CONFIG" ]; then
        API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' "$SYNCTHING_CONFIG")
    fi

    if [ -n "$API_KEY" ] && curl -s -H "X-API-Key: $API_KEY" "$SYNCTHING_URL/rest/system/ping" | grep -q "pong"; then
        FOLDERS=$(curl -s -H "X-API-Key: $API_KEY" "$SYNCTHING_URL/rest/config/folders")
        if [[ "$FOLDERS" != *"$HUB_PATH"* ]]; then
             clear
            $GUM style --border double --foreground 212 "⚠️  SYNCTHING ACTION REQUIRED" \
                "The folder '$HUB_PATH' is not yet in Syncthing." \
                " " \
                "1. Open Syncthing WebUI" \
                "2. Add Folder -> Path: $HUB_PATH" \
                "3. Label: Cloud Saves"
            
            if $GUM confirm "Open WebUI now?"; then xdg-open "$SYNCTHING_URL"; fi
        fi
    else
        echo "⚠️  Syncthing not detected. Sync will happen once you start it."
    fi
}

# --- 2. Game Selector (GBM Aware) ---
select_game() {
    APPID_LIST=""
    
    # A. Parse the GBM Service File for Priority Games
    if [ -f "$GBM_SERVICE_FILE" ]; then
        # Extract AppIDs from ExecStart line
        APPID_LIST=$(grep "^ExecStart=" "$GBM_SERVICE_FILE" | sed 's|ExecStart=.*/backup_prefixes_incremental.sh *||')
    fi

    if [ -n "$APPID_LIST" ]; then
        $GUM style --foreground 212 "📂 Reading Backup Schedule (GBM)..."
        
        TEMP_LIST="/tmp/cloud_candidates.txt"
        rm -f "$TEMP_LIST"
        
        # Iterate through AppIDs found in GBM
        for APPID in $APPID_LIST; do
            # 1. Try Lookup File (Non-Steam)
            NAME=$(grep "^$APPID," "$GBM_LOOKUP_FILE" | cut -d',' -f2)
            
            # 2. Try Steam Manifest (Steam)
            if [ -z "$NAME" ]; then
                MANIFEST=$(find "$HOME/.local/share/Steam/steamapps" -name "appmanifest_$APPID.acf" -print -quit)
                if [ -f "$MANIFEST" ]; then
                    NAME=$(grep -Po '"name"\s+"\K.*(?=")' "$MANIFEST" | head -1)
                fi
            fi
            
            # 3. Default if unknown
            if [ -z "$NAME" ]; then NAME="Unknown Game ($APPID)"; fi
            
            # Check if already synced (GBM Map File)
            STATUS=""
            if grep -q "^$APPID," "$GBM_MAP_FILE"; then STATUS="[✔️ Synced]"; else STATUS="[  Backup Only]"; fi
            
            echo "$STATUS $NAME | $APPID" >> "$TEMP_LIST"
        done
        
        # B. Fallback Option
        echo "[➕ Scan All Installed Games] | SCAN_ALL" >> "$TEMP_LIST"
        
        CHOICE=$($GUM filter --placeholder "Select from Backup List..." < "$TEMP_LIST")
    else
        CHOICE="SCAN_ALL"
    fi

    # Handle Selection
    if [[ "$CHOICE" == *"SCAN_ALL"* ]]; then
        $GUM style --foreground 240 "ℹ️  Scanning full Steam library..."
        TEMP_LIST="/tmp/cloud_games.txt"
        rm -f "$TEMP_LIST"
        find "$HOME/.local/share/Steam/steamapps" -name "appmanifest_*.acf" | while read manifest; do
            APPID=$(grep -Po '"appid"\s+"\K[0-9]+' "$manifest" | head -1)
            NAME=$(grep -Po '"name"\s+"\K.*(?=")' "$manifest" | head -1)
            echo "$NAME | $APPID" >> "$TEMP_LIST"
        done
        CHOICE=$($GUM filter --placeholder "Select Installed Game..." < "$TEMP_LIST")
    fi

    if [ -z "$CHOICE" ]; then exit 0; fi
    
    # Extract ID and Name
    SELECTED_ID=$(echo "$CHOICE" | awk -F'|' '{print $NF}' | xargs)
    SELECTED_NAME=$(echo "$CHOICE" | awk -F'|' '{print $1}' | sed 's/\[.*\] //' | xargs)
    CLEAN_NAME=$(echo "$SELECTED_NAME" | tr -cd '[:alnum:]_-')
}

# --- 3. The Detective (Wiki Scraper) ---
find_local_path() {
    COMPAT_PATH="$HOME/.local/share/Steam/steamapps/compatdata/$SELECTED_ID/pfx/drive_c/users/steamuser"
    
    ACTION=$($GUM choose --header "Locate Saves for: $SELECTED_NAME" \
        "🕵️  Auto-Detective (Wiki Scrape)" \
        "📂  Manual Browse" \
        "CANCEL")

    case "$ACTION" in
        "🕵️  Auto-Detective"*)
            $GUM style --foreground 212 "🌐 Contacting PCGamingWiki..."
            SEARCH_URL="https://www.pcgamingwiki.com/w/index.php?search=$(echo "$SELECTED_NAME" | sed 's/ /+/g')"
            PAGE_CONTENT=$(curl -L -s "$SEARCH_URL")
            
            HINT=""
            if echo "$PAGE_CONTENT" | grep -q "My Games"; then HINT="Documents/My Games"; fi
            if echo "$PAGE_CONTENT" | grep -q "AppData"; then HINT="AppData"; fi
            if echo "$PAGE_CONTENT" | grep -q "Saved Games"; then HINT="Saved Games"; fi
            
            if [ -n "$HINT" ]; then
                $GUM style --foreground 120 "💡 Wiki Hint: Looked for '$HINT'"
                FOUND_PATH=$(find "$COMPAT_PATH" -type d -name "*$HINT*" 2>/dev/null | head -1)
                
                if [ -d "$FOUND_PATH" ]; then
                    $GUM style --foreground 212 "🎉 FOUND IT! Opening File Manager..."
                    xdg-open "$FOUND_PATH"
                    if $GUM confirm "Is this the correct save folder?"; then
                        LOCAL_PATH="$FOUND_PATH"
                    else
                        find_local_path; return
                    fi
                else
                    $GUM style --foreground 196 "❌ Hint found ($HINT) but folder missing."
                    xdg-open "$SEARCH_URL"
                    find_local_path; return
                fi
            else
                $GUM style --foreground 196 "❌ Could not scrape path. Opening Wiki..."
                xdg-open "$SEARCH_URL"
                find_local_path; return
            fi
            ;;
            
        "📂  Manual Browse"*)
            LOCAL_PATH=$($GUM file "$COMPAT_PATH" --directory)
            ;;
            
        *) exit 0 ;;
    esac

    if [ -z "$LOCAL_PATH" ]; then exit 0; fi
    $GUM style --foreground 120 "✅ Path Confirmed:" "$LOCAL_PATH"
}

# --- 4. Generate Wrapper & Update GBM Map ---
generate_script() {
    CLOUD_PATH="$HUB_PATH/$CLEAN_NAME"
    mkdir -p "$CLOUD_PATH"
    
    WRAPPER_NAME="launch_${CLEAN_NAME}.sh"
    WRAPPER_PATH="$HOME/.local/bin/$WRAPPER_NAME"
    
    # Create standard wrapper
    cat > "$WRAPPER_PATH" <<EOF
#!/bin/bash
# Cloud Save Wrapper: $SELECTED_NAME
# -------------------------------------------------------
HUB="$CLOUD_PATH"
LOCAL="$LOCAL_PATH"

# A. SMART PULL (Hub -> Local)
if [ "\$(ls -A \$HUB)" ]; then
    echo "☁️  Downloading Saves..."
    rsync -av --delete "\$HUB/" "\$LOCAL/"
else
    echo "⚠️  First Run. Uploading Local to Cloud..."
    rsync -av "\$LOCAL/" "\$HUB/"
fi

# B. PLAY
echo "🎮 Launching Game..."
"\$@"
EXIT_CODE=\$?

# C. PUSH (Local -> Hub)
echo "☁️  Uploading Saves..."
rsync -av --delete "\$LOCAL/" "\$HUB/"

exit \$EXIT_CODE
EOF
    chmod +x "$WRAPPER_PATH"

    # --- UPDATE GAME BACKUP MANAGER (GBM) ---
    # We write to the map file so your other tool knows this game is synced.
    # Format: AppID,LivePath,RepoPath
    if [ -f "$GBM_MAP_FILE" ]; then
        # Remove old entry if exists
        sed -i "/^$SELECTED_ID,/d" "$GBM_MAP_FILE"
        # Add new entry
        echo "$SELECTED_ID,$LOCAL_PATH,$CLOUD_PATH" >> "$GBM_MAP_FILE"
        $GUM style --foreground 240 "📝 Updated Backup Manager Sync Map."
    fi
    
    clear
    $GUM style --border double --foreground 120 "✅ WRAPPER CREATED" \
        "1. Open Steam Properties for $SELECTED_NAME" \
        "2. Launch Options:" \
        "   $WRAPPER_PATH %command%"
    read -p "Press Enter..."
}

# --- Flow ---
setup_storage
select_game
find_local_path
generate_scriptcloud_save_setup.sh
