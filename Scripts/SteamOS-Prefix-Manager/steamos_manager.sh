#!/bin/bash
# === SteamOS Backup Manager (v1.2 - Gum Edition) ===

# --- Global Paths ---
SCRIPTS_DIR="$HOME/scripts"
BIN_DIR="$SCRIPTS_DIR/bin"
SERVICE_FILE="$HOME/.config/systemd/user/steamos-prefix-backup.service"
TIMER_FILE="$HOME/.config/systemd/user/steamos-prefix-backup.timer"
MANAGER_SCRIPT_PATH="$SCRIPTS_DIR/steamos_manager.sh"
CONFIG_FILE="$SCRIPTS_DIR/backup_config.conf"
LOOKUP_FILE="$SCRIPTS_DIR/non_steam_games.csv"
LOG_FILE="$SCRIPTS_DIR/backup_log.log"
SAVE_SYNC_MAP_FILE="$SCRIPTS_DIR/save_sync_map.csv"
SAVE_WRAPPER_SCRIPT="$SCRIPTS_DIR/save_wrapper.sh"

export PATH="$BIN_DIR:$PATH"

# Detect Steam root
STEAM_ROOT_DIR=""
if [ -d "$HOME/.local/share/Steam" ]; then
    STEAM_ROOT_DIR="$HOME/.local/share/Steam"
elif [ -d "$HOME/.steam/steam" ]; then
    STEAM_ROOT_DIR="$HOME/.steam/steam"
fi
PREFIX_DIR="$HOME/.steam/steam/steamapps/compatdata"
SYSTEMD_DIR="$HOME/.config/systemd/user"

# Session-level game list cache
GAME_LIST_CACHE=""

################################################################################
# SECTION 1: BOOTLOADER
################################################################################

function check_dependencies() {
    mkdir -p "$BIN_DIR"

    if ! command -v gum &> /dev/null; then
        clear; echo "⚙️  Initializing Interface (Downloading 'gum')..."
        curl -L -o "$SCRIPTS_DIR/gum.tar.gz" "https://github.com/charmbracelet/gum/releases/download/v0.13.0/gum_0.13.0_Linux_x86_64.tar.gz"
        if [ -f "$SCRIPTS_DIR/gum.tar.gz" ]; then
            tar -xzf "$SCRIPTS_DIR/gum.tar.gz" -C "$SCRIPTS_DIR"
            GUM_BIN=$(find "$SCRIPTS_DIR" -name "gum" -type f ! -path "*/bin/*" | head -n 1)
            if [ -n "$GUM_BIN" ]; then
                mv "$GUM_BIN" "$BIN_DIR/"
                chmod +x "$BIN_DIR/gum"
            fi
            rm -rf "$SCRIPTS_DIR/gum.tar.gz"
            find "$SCRIPTS_DIR" -maxdepth 1 -type d -name "gum*" -exec rm -rf {} + 2>/dev/null
        else
            echo "❌ Failed to download gum. Please check internet connection."
            exit 1
        fi
    fi

    if ! command -v jq &> /dev/null; then
        echo "⚙️  Initializing Tools (Downloading 'jq')..."
        curl -L -o "$BIN_DIR/jq" "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64"
        chmod +x "$BIN_DIR/jq"
    fi
}

# --- GUM THEME ---
GUM_OPTS="--cursor.foreground=212 --item.foreground=250 --selected.foreground=212 --header.foreground=99"

function ui_header() {
    clear
    gum style \
        --foreground 99 --border-foreground 99 --border double \
        --align center --width 50 --margin "1 1" --padding "0 2" \
        "$1"
}

function ui_choose() {
    local header="$1"; shift
    gum choose $GUM_OPTS --header "$header" "$@"
}

function ui_confirm() {
    gum confirm "$1" \
        --affirmative "Yes" --negative "No" \
        --selected.background=212 --selected.foreground=0
}

function ui_confirm_danger() {
    gum style \
        --foreground 196 --border-foreground 196 --border double \
        --align center --width 50 --margin "1 1" --padding "0 2" \
        "⚠️  WARNING" "$1"
    gum confirm "Are you sure?" \
        --affirmative "Yes, Continue" --negative "Cancel" \
        --selected.background=196 --selected.foreground=0
}

function ui_input() {
    gum input --placeholder "$1" --width 50 --value "${2:-}"
}

# --- HELPER SCRIPTS ---

function write_save_wrapper_script() {
    cat << 'EOF' > "$SAVE_WRAPPER_SCRIPT"
#!/bin/bash
# === Save Sync Wrapper (PULL/PLAY/PUSH) ===
LOG_FILE="$HOME/scripts/backup_log.log"
MAP_FILE="$HOME/scripts/save_sync_map.csv"
export PATH="$HOME/scripts/bin:$PATH"

function write_log() {
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    (echo "[$timestamp] [$1] $2"; cat "$LOG_FILE" 2>/dev/null | head -n 49) > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

if [ "$#" -lt 2 ]; then
    write_log "WRAPPER-ERROR" "Not enough arguments."
    exit 1
fi

APPID=$1; shift; GAME_COMMAND=("$@")
MAP_ENTRY=$(grep "^$APPID," "$MAP_FILE")

if [ -z "$MAP_ENTRY" ]; then
    write_log "WRAPPER-ERROR" "No map entry for $APPID"
    "${GAME_COMMAND[@]}"
    exit 0
fi

LIVE=$(echo "$MAP_ENTRY" | cut -d',' -f2)
REPO=$(echo "$MAP_ENTRY" | cut -d',' -f3)

[ ! -d "$LIVE" ] && mkdir -p "$LIVE"
[ ! -d "$REPO" ] && mkdir -p "$REPO"

write_log "WRAPPER-PULL" "Syncing Repo -> Live ($APPID)"
rsync -a --delete "$REPO/" "$LIVE/"

write_log "WRAPPER-PLAY" "Launching ($APPID)"
"${GAME_COMMAND[@]}"
RET=$?

write_log "WRAPPER-PUSH" "Syncing Live -> Repo ($APPID)"
rsync -a --delete "$LIVE/" "$REPO/"

exit $RET
EOF
    chmod +x "$SAVE_WRAPPER_SCRIPT"
}

function update_helper_scripts() {
    check_dependencies

    cat << 'EOF' > "$SCRIPTS_DIR/backup_prefixes_incremental.sh"
#!/bin/bash
set -e
CONFIG_FILE="$HOME/scripts/backup_config.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
export PATH="$HOME/scripts/bin:$PATH"

if [ ! -d "$SD_CARD_PATH" ]; then echo "CRITICAL: SD Card not found at $SD_CARD_PATH"; exit 1; fi

STEAM_ROOT_DIR="$HOME/.local/share/Steam"
[ ! -d "$STEAM_ROOT_DIR" ] && STEAM_ROOT_DIR="$HOME/.steam/steam"

LOOKUP_FILE="$HOME/scripts/non_steam_games.csv"
LOG_FILE="$HOME/scripts/backup_log.log"
BACKUP_DEST_DIR="$SD_CARD_PATH/steamos_restore/prefix_backups"
PREFIX_DIR="$HOME/.steam/steam/steamapps/compatdata"

function write_log() {
    local t=$(date "+%Y-%m-%d %H:%M:%S")
    (echo "[$t] [$1] [$2] Games: $3"; cat "$LOG_FILE" 2>/dev/null | head -n 49) > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
}

function check_cloud() {
    local id=$1
    local userdata=$(find "$STEAM_ROOT_DIR/userdata" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' | head -n 1)
    [ -f "$userdata/$id/remotecache.vdf" ] && return 0
    local manifest=$(find "$STEAM_ROOT_DIR/steamapps" -name "appmanifest_$id.acf" | head -n 1)
    if [ -f "$manifest" ] && grep -qi "CloudSaveFiles\|CloudGameSaves\|\"cloudsaves\"" "$manifest"; then return 0; fi
    return 1
}

function main() {
    local TYPE="Scheduled"
    [[ " $* " == *" --manual "* ]] && TYPE="Manual"
    declare -a backed=()
    declare -a failed=()

    for appid in "$@"; do
        [ "$appid" == "--manual" ] && continue
        local name="" do_back=false
        local manifest=$(find "$STEAM_ROOT_DIR/steamapps" -name "appmanifest_$appid.acf" | head -n 1)

        if [ -f "$manifest" ]; then
            name=$(grep '"name"' "$manifest" | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
            [[ "$name" =~ ^(Proton|Steamworks|Steam Linux Runtime|Steam) ]] && continue
            if check_cloud "$appid"; then echo "Skipping Cloud: $name"; continue; fi
            do_back=true
        else
            name=$(grep "^$appid," "$LOOKUP_FILE" | cut -d',' -f2)
            [ -z "$name" ] && name="NonSteam_$appid"
            do_back=true
        fi

        if [ "$do_back" = true ]; then
            local safe=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')
            local src="$PREFIX_DIR/$appid/"
            local dst="$BACKUP_DEST_DIR/$safe/$appid/"
            mkdir -p "$BACKUP_DEST_DIR/$safe"
            if [ -d "$src" ]; then
                rsync -a --delete "$src" "$dst"
                [ $? -eq 0 ] && backed+=("$name") || failed+=("$name")
            fi
        fi
    done

    [ ${#backed[@]} -gt 0 ] && write_log "SUCCESS" "$TYPE" "${backed[*]}"
    [ ${#failed[@]} -gt 0 ] && write_log "FAILED"  "$TYPE" "${failed[*]}"
    cp -rT "$HOME/scripts/" "$SD_CARD_PATH/steamos_restore/scripts/"
}
main "$@"
EOF
    chmod +x "$SCRIPTS_DIR/backup_prefixes_incremental.sh"
    write_save_wrapper_script
}

function install_desktop_shortcut() {
    cat << EOF > "$HOME/Desktop/Backup Manager.desktop"
[Desktop Entry]
Name=Backup Manager
Comment=Manage Game Backups
Exec=konsole -e bash $MANAGER_SCRIPT_PATH
Icon=utilities-terminal
Type=Application
Categories=Utility;
EOF
    chmod +x "$HOME/Desktop/Backup Manager.desktop"
    gio set "$HOME/Desktop/Backup Manager.desktop" metadata::trusted true 2>/dev/null
}

function install_systemd_files() {
    mkdir -p "$SYSTEMD_DIR"
    cat << EOF > "$SYSTEMD_DIR/steamos-prefix-backup.service"
[Unit]
Description=Weekly incremental backup of Wine prefixes
[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/backup_prefixes_incremental.sh
EOF
    cat << EOF > "$SYSTEMD_DIR/steamos-prefix-backup.timer"
[Unit]
Description=Run weekly on Sunday at 19:00
[Timer]
OnCalendar=Sun *-*-* 19:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
}

################################################################################
# SECTION 2: HELPERS
################################################################################

function detect_sd_card() {
    local media_dir="/run/media/deck"
    local cards=()
    for d in "$media_dir"/*/; do
        [ -d "$d" ] && cards+=("${d%/}")
    done

    if [ ${#cards[@]} -eq 0 ]; then
        echo ""
    elif [ ${#cards[@]} -eq 1 ]; then
        echo "${cards[0]}"
    else
        local names=()
        for c in "${cards[@]}"; do names+=("$(basename "$c")"); done
        local choice=$(printf '%s\n' "${names[@]}" | gum choose $GUM_OPTS --header "Multiple SD cards found — select one")
        [ -n "$choice" ] && echo "$media_dir/$choice" || echo ""
    fi
}

function get_name_from_shortcuts() {
    local id=$1
    for d in "$STEAM_ROOT_DIR"/userdata/[0-9]*; do
        local f="$d/config/shortcuts.vdf"
        [ -f "$f" ] || continue
        local name
        if command -v strings &>/dev/null; then
            name=$(strings "$f" | grep -A 5 "^$id$" | grep -v "^$id$" | head -n 1)
        else
            name=$(cat "$f" | tr -cd '[:print:]\n' | grep -A 5 "^$id$" | grep -v "^$id$" | head -n 1)
        fi
        [ -n "$name" ] && echo "$name" && return
    done
}

function get_game_name() {
    local id=$1
    local n=$(grep "^$id," "$LOOKUP_FILE" 2>/dev/null | cut -d',' -f2)
    [ -n "$n" ] && echo "$n" && return
    local m=$(find "$STEAM_ROOT_DIR/steamapps" -name "appmanifest_$id.acf" 2>/dev/null | head -n 1)
    if [ -f "$m" ]; then grep '"name"' "$m" | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/'; return; fi
    local s=$(get_name_from_shortcuts "$id")
    [ -n "$s" ] && echo "$s" && return
    echo "Unknown ($id)"
}

function get_scheduled_ids() {
    grep "^ExecStart=" "$SERVICE_FILE" 2>/dev/null \
        | sed 's|ExecStart=.*/backup_prefixes_incremental.sh *||'
}

function get_scheduled_count() {
    get_scheduled_ids | tr ' ' '\n' | grep -c '^[0-9]' || echo 0
}

function get_launch_options_hack() {
    local f=""
    for d in "$STEAM_ROOT_DIR"/userdata/[0-9]*; do
        [ -f "$d/config/shortcuts.vdf" ] && f="$d/config/shortcuts.vdf" && break
    done
    [ -z "$f" ] && echo "" && return
    local p=$(printf "\\x01appid\\x00%s\\x00" "$1")
    local l=$(grep -a -A 10 "$p" "$f" | grep -a "\\x01LaunchOptions\\x00" | head -n 1)
    [ -n "$l" ] && echo "$l" | cut -d$'\x00' -f4 | sed 's/"//g' || echo ""
}

function build_game_list() {
    local curr=$(get_scheduled_ids)

    # Single upfront pass for cloud save detection
    local userdata=$(find "$STEAM_ROOT_DIR/userdata" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' | head -n 1)
    local cloud_ids=""
    [ -n "$userdata" ] && cloud_ids=$(find "$userdata" -name "remotecache.vdf" 2>/dev/null \
        | sed -E 's|.*/([0-9]+)/remotecache\.vdf|\1|')

    # Process substitution keeps variables in scope (no subshell)
    while IFS= read -r m; do
        local id=$(grep '"appid"' "$m" | sed -E 's/.*"appid"[[:space:]]+"([^"]+)".*/\1/')
        local name=$(grep '"name"' "$m" | sed -E 's/.*"name"[[:space:]]+"([^"]+)".*/\1/')
        [[ "$name" =~ ^(Proton|Steamworks|Steam Linux Runtime|Steam) ]] && continue

        local is_cloud=0
        echo "$cloud_ids" | grep -qx "$id" && is_cloud=1
        if [ "$is_cloud" -eq 0 ] && grep -qi "CloudSaveFiles\|CloudGameSaves\|\"cloudsaves\"" "$m" 2>/dev/null; then
            is_cloud=1
        fi

        local is_sched=0
        [[ " $curr " == *" $id "* ]] && is_sched=1
        echo "$id|$name|$is_cloud|$is_sched"
    done < <(find "$STEAM_ROOT_DIR/steamapps" -name "appmanifest_*.acf" 2>/dev/null)

    # Non-Steam prefixes
    for d in "$PREFIX_DIR"/*/; do
        local id=$(basename "$d"); [ "$id" == "0" ] && continue
        [ -f "$STEAM_ROOT_DIR/steamapps/appmanifest_$id.acf" ] && continue
        local name=$(get_game_name "$id")
        local is_sched=0; [[ " $curr " == *" $id "* ]] && is_sched=1
        echo "$id|$name|0|$is_sched"
    done
}

function get_game_list_cached() {
    if [ -z "$GAME_LIST_CACHE" ]; then
        GAME_LIST_CACHE=$(build_game_list | sort -t'|' -k2)
    fi
    echo "$GAME_LIST_CACHE"
}

function invalidate_game_list_cache() {
    GAME_LIST_CACHE=""
}

function safe_vdf_edit() {
    local game_name="$1"
    local appid="$2"

    # Warn user before killing Steam
    clear
    gum style \
        --foreground 214 --border-foreground 214 --border double \
        --align center --width 50 --margin "1 1" --padding "1 2" \
        "⚠️  CONTROLLER WARNING" \
        "" \
        "Steam must be closed to safely edit shortcuts." \
        "" \
        "Your controller will stop responding until" \
        "Steam restarts. This is normal — sit tight." \
        "" \
        "The script will continue running in the background."

    sleep 4

    # Kill Steam and wait for it to fully exit
    gum style --foreground 250 "  🔴 Closing Steam..."
    steam -shutdown 2>/dev/null
    sleep 2
    # Force kill if still running
    if pgrep -x steam &>/dev/null; then
        killall -TERM steam 2>/dev/null
        sleep 3
    fi

    # Edit the VDF
    gum style --foreground 250 "  ✏️  Updating shortcuts..."
    local result
    result=$(restore_nonsteam_prefix_mapping "$game_name" "$appid" 2>&1)

    # Relaunch Steam
    gum style --foreground 250 "  🟢 Restarting Steam..."
    nohup steam &>/dev/null &
    sleep 2

    # Show result
    if echo "$result" | grep -q "NOT_FOUND"; then
        gum style --foreground 212 \
            "⚠️  '$game_name' not found in Steam shortcuts — remap manually."
    else
        gum style --foreground 46 \
            "✅ Shortcut remapped successfully."
    fi

    gum style --foreground 240 \
        "  🎮 Controller will return once Steam finishes loading..."
    sleep 3
}

# Updates shortcuts.vdf AppID for a non-Steam game to match a restored prefix
function restore_nonsteam_prefix_mapping() {
    local game_name="$1"
    local backup_appid="$2"

    python3 << PYEOF
import os, struct

steam_root = os.path.expanduser("~/.local/share/Steam")
if not os.path.exists(steam_root):
    steam_root = os.path.expanduser("~/.steam/steam")

game_name = """$game_name"""
backup_appid = $backup_appid

updated = False
userdata_dir = os.path.join(steam_root, "userdata")
if not os.path.exists(userdata_dir):
    print("No userdata directory found")
    exit(1)

for uid in os.listdir(userdata_dir):
    vdf_path = os.path.join(userdata_dir, uid, "config", "shortcuts.vdf")
    if not os.path.exists(vdf_path):
        continue

    with open(vdf_path, 'rb') as f:
        data = f.read()

    # Find AppName field matching our game
    name_bytes = b'\x01AppName\x00' + game_name.encode('utf-8') + b'\x00'
    pos = data.find(name_bytes)

    if pos == -1:
        continue

    # Find appid field in the 100 bytes before the name
    chunk = data[max(0, pos - 100):pos]
    appid_marker = b'\x02appid\x00'
    appid_pos = chunk.rfind(appid_marker)

    if appid_pos == -1:
        continue

    abs_pos = max(0, pos - 100) + appid_pos + len(appid_marker)
    current_appid = struct.unpack('<I', data[abs_pos:abs_pos + 4])[0]

    if current_appid == backup_appid:
        print(f"AppID already matches: {backup_appid}")
        updated = True
        break

    # Backup before writing
    with open(vdf_path + '.bak', 'wb') as f:
        f.write(data)

    new_data = data[:abs_pos] + struct.pack('<I', backup_appid) + data[abs_pos + 4:]

    with open(vdf_path, 'wb') as f:
        f.write(new_data)

    print(f"Updated AppID from {current_appid} to {backup_appid}")
    updated = True
    break

if not updated:
    print("NOT_FOUND")
    exit(1)
PYEOF
}

function scan_drive_c_for_name() {
    local drive_c="$1"
    local skip="^(Microsoft|Windows|Temp|Adobe|My Games|My Music|My Pictures|My Videos|Default|Public|steam_api|DirectX|Common Files|WindowsApps|Packages|Internet Explorer|Windows NT)$"
    declare -A name_count

    for loc in \
        "$drive_c/Program Files" \
        "$drive_c/Program Files (x86)" \
        "$drive_c/users/steamuser/AppData/Local" \
        "$drive_c/users/steamuser/AppData/Roaming" \
        "$drive_c/users/steamuser/Documents"; do
        [ -d "$loc" ] || continue
        for d in "$loc"/*/; do
            [ -d "$d" ] || continue
            local n=$(basename "$d")
            [[ "$n" =~ $skip ]] && continue
            name_count[$n]=$((${name_count[$n]:-0} + 1))
        done
    done

    # Output names sorted by frequency — most seen = most likely the game
    for n in "${!name_count[@]}"; do
        echo "${name_count[$n]} $n"
    done | sort -rn | awk '{print $2}'
}

function find_prefix() {
    ui_header "🔍 FIND A PREFIX"
    gum style --foreground 240 "  Tip: Copy and paste the path from Dolphin file manager"
    echo ""

    local search_dir=$(ui_input "Enter directory path to search")
    [ -z "$search_dir" ] && return

    if [ ! -d "$search_dir" ]; then
        gum style --foreground 196 "❌ Directory not found: $search_dir"
        sleep 2; return
    fi

    local tmpfile=$(mktemp)
    gum spin --title "🔍 Scanning for prefixes..." -- bash -c "
        find '$search_dir' -type d -name 'drive_c' 2>/dev/null \
            | grep -E '/[0-9]+/pfx/drive_c$' > '$tmpfile'
    "

    if [ ! -s "$tmpfile" ]; then
        rm -f "$tmpfile"
        gum style --foreground 212 "No Wine prefixes found in that directory."
        sleep 2; return
    fi

    local resultsfile=$(mktemp)

    while IFS= read -r drive_c; do
        local pfx_dir=$(dirname "$drive_c")
        local id_dir=$(dirname "$pfx_dir")
        local name_dir=$(dirname "$id_dir")
        local appid=$(basename "$id_dir")
        local folder_name=$(basename "$name_dir")

        [[ "$appid" =~ ^[0-9]+$ ]] || continue

        local name="" confidence=""

        if [[ "$folder_name" =~ ^[0-9]+$ ]] || [[ "$folder_name" == Unknown_* ]]; then
            # Unknown folder — scan drive_c to identify
            local scan=$(scan_drive_c_for_name "$drive_c")
            if [ -n "$scan" ]; then
                local top=$(echo "$scan" | head -n 1)
                local count=$(echo "$scan" | wc -l | tr -d ' ')
                name="$top"
                [ "$count" -ge 3 ] && confidence="High" || \
                [ "$count" -ge 2 ] && confidence="Medium" || confidence="Low"
            else
                name="Unknown ($appid)"
                confidence="Low"
            fi
        else
            # Named folder — trust it
            name=$(echo "$folder_name" | sed 's/_/ /g')
            confidence="High"
        fi

        echo "$appid|$name|$confidence|$drive_c"
    done < "$tmpfile"  > "$resultsfile"
    rm -f "$tmpfile"

    if [ ! -s "$resultsfile" ]; then
        rm -f "$resultsfile"
        gum style --foreground 212 "No valid prefixes could be identified."
        sleep 2; return
    fi

    local labels=()
    declare -A label_to_appid
    declare -A label_to_prefix_src
    declare -A label_to_name

    while IFS='|' read -r appid name confidence drive_c; do
        local icon="✅"
        [ "$confidence" == "Medium" ] && icon="🟡"
        [ "$confidence" == "Low"    ] && icon="❓"
        local label="$icon $name — ID: $appid ($confidence)"
        labels+=("$label")
        label_to_appid["$label"]="$appid"
        label_to_prefix_src["$label"]="$(dirname "$(dirname "$drive_c")")"
        label_to_name["$label"]="$name"
    done < "$resultsfile"
    rm -f "$resultsfile"

    ui_header "🔍 PREFIXES FOUND"
    gum style --foreground 240 "  TAB to select  •  ENTER to restore  •  ESC to cancel"
    echo ""

    local selection
    selection=$(printf '%s\n' "${labels[@]}" | gum choose --no-limit \
        --cursor.foreground=212 \
        --item.foreground=250 \
        --selected.foreground=212 \
        --header "")

    [ -z "$selection" ] && return

    while IFS= read -r line; do
        local appid="${label_to_appid[$line]}"
        local src="${label_to_prefix_src[$line]}"
        local name="${label_to_name[$line]}"

        if ui_confirm "Restore '$name' (AppID: $appid) to compatdata?"; then
            mkdir -p "$PREFIX_DIR/$appid"
            gum spin --title "🔄 Restoring $name..." -- \
                rsync -a --delete "$src/" "$PREFIX_DIR/$appid/"

            # Non-Steam: offer VDF remap
            if [ ! -f "$STEAM_ROOT_DIR/steamapps/appmanifest_$appid.acf" ]; then
                if ui_confirm "🎮 Update Steam shortcut to point to this prefix?"; then
                    safe_vdf_edit "$name" "$appid"
                fi
            fi

            gum style --foreground 46 "✅ $name restored!"; sleep 1
        fi
    done <<< "$selection"

    ui_header "✅ Done!"; sleep 1
}

################################################################################
# SECTION 3: MANAGE SCHEDULE
################################################################################

function manage_backup_schedule() {
    if [ ! -f "$SERVICE_FILE" ]; then
        gum style --foreground 196 "❌ Service file not found. Please reinstall."
        sleep 2; return
    fi

    ui_header "📋 MANAGE SCHEDULE"
    local filter=$(ui_choose "Show which games?" \
        "💾 Non-Cloud Only" \
        "🌐 Cloud Games Only" \
        "📋 All Games" \
        "⬅️  Back")

    [ "$filter" == "⬅️  Back" ] || [ -z "$filter" ] && return

    local tmpfile=$(mktemp)
    get_game_list_cached > "$tmpfile"

    local labels=()
    declare -A label_to_id
    declare -A label_is_cloud

    while IFS='|' read -r id name is_cloud is_sched; do
        case "$filter" in
            "💾 Non-Cloud Only")   [ "$is_cloud" -eq 1 ] && continue ;;
            "🌐 Cloud Games Only") [ "$is_cloud" -eq 0 ] && continue ;;
        esac

        local label
        if [ "$is_cloud" -eq 1 ]; then
            label="🌐 $name (Cloud)"
        elif [ "$is_sched" -eq 1 ]; then
            label="✅ $name"
        else
            label="☐  $name"
        fi

        labels+=("$label")
        label_to_id["$label"]="$id"
        label_is_cloud["$label"]="$is_cloud"
    done < "$tmpfile"
    rm -f "$tmpfile"

    if [ ${#labels[@]} -eq 0 ]; then
        gum style --foreground 212 "No games found for this filter."; sleep 1; return
    fi

    ui_header "📋 SELECT GAMES TO SCHEDULE"
    gum style --foreground 240 "  TAB to toggle  •  ENTER to save  •  ESC to cancel"
    echo ""

    local selection
    selection=$(printf '%s\n' "${labels[@]}" | gum choose --no-limit \
        --cursor.foreground=212 \
        --item.foreground=250 \
        --selected.foreground=212 \
        --header "")

    [ -z "$selection" ] && return

    local new_schedule=""
    while IFS= read -r line; do
        [ "${label_is_cloud[$line]:-0}" -eq 1 ] && continue
        local eid="${label_to_id[$line]:-}"
        [ -n "$eid" ] && new_schedule+="$eid "
    done <<< "$selection"

    gum spin --title "💾 Saving schedule..." -- sleep 1
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Weekly incremental backup of specified Wine prefixes
[Service]
Type=oneshot
ExecStart=$SCRIPTS_DIR/backup_prefixes_incremental.sh $new_schedule
EOF
    systemctl --user daemon-reload
    invalidate_game_list_cache
    ui_header "✅ Schedule Updated!"
    sleep 1
}

################################################################################
# SECTION 4: BACKUP ACTIONS
################################################################################

function manual_backup() {
    local curr=$(get_scheduled_ids)
    if [ -z "$(echo $curr | tr -d ' ')" ]; then
        gum style --foreground 212 "⚠️  No games scheduled. Use 'Manage Schedule' first."
        sleep 2; return
    fi
    ui_header "▶️  RUN BACKUP NOW"
    echo " Backing up scheduled games..."
    echo ""
    "$SCRIPTS_DIR/backup_prefixes_incremental.sh" --manual $curr
    echo ""
    gum confirm "✅ Backup complete!" --affirmative "OK" --negative ""
}

function create_restore_point() {
    source "$CONFIG_FILE"
    if [ ! -d "$SD_CARD_PATH" ]; then
        gum style --foreground 196 "❌ SD Card not found at $SD_CARD_PATH"; sleep 2; return
    fi
    if ! ui_confirm "📸 Create full restore point on SD Card?"; then return; fi

    local rd="$SD_CARD_PATH/steamos_restore"
    gum spin --title "📸 Backing up configs..." -- bash -c "
        mkdir -p '$rd/prefix_backups' '$rd/scripts' '$rd/Syncthing' '$rd/syncthing_config'
        rsync -a '$HOME/scripts/' '$rd/scripts/'
        [ -d '$HOME/Syncthing/GameSaves' ] && rsync -a '$HOME/Syncthing/GameSaves/' '$rd/Syncthing/GameSaves/'
        [ -d '$HOME/.config/syncthing' ] && rsync -a '$HOME/.config/syncthing/' '$rd/syncthing_config/'
    "

    local curr=$(get_scheduled_ids)
    for id in $curr; do
        local name=$(get_game_name "$id")
        local safe=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')
        local src="$PREFIX_DIR/$id/"
        local dst="$rd/prefix_backups/$safe/$id/"
        mkdir -p "$(dirname "$dst")"
        [ -d "$src" ] && gum spin --title "💾 Backing up $name..." -- rsync -a "$src" "$dst"
    done

    ui_header "✅ Restore Point Created!"; sleep 2
}

################################################################################
# SECTION 5: RESTORE ACTIONS
################################################################################

function restore_single_game() {
    source "$CONFIG_FILE"
    if [ ! -d "$SD_CARD_PATH" ]; then
        gum style --foreground 196 "❌ SD Card not found at $SD_CARD_PATH"; sleep 2; return
    fi

    local backup_root="$SD_CARD_PATH/steamos_restore/prefix_backups"
    local list=()
    for d in "$backup_root"/*/; do
        [ -d "$d" ] || continue
        list+=("$(basename "$d")")
    done

    if [ ${#list[@]} -eq 0 ]; then
        gum style --foreground 212 "No backups found on SD card."; sleep 1; return
    fi

    ui_header "🎮 RESTORE A GAME"
    local sel=$(printf '%s\n' "${list[@]}" | gum choose $GUM_OPTS --header "Select game to restore")
    [ -z "$sel" ] && return

    local id_dir=$(find "$backup_root/$sel" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    local id=$(basename "$id_dir")

    if ui_confirm "Overwrite current prefix for $sel?"; then
        gum spin --title "🔄 Restoring $sel..." -- rsync -a --delete "$id_dir/" "$PREFIX_DIR/$id/"

        # Non-Steam game: offer to remap shortcuts.vdf to match restored prefix
        if [ ! -f "$STEAM_ROOT_DIR/steamapps/appmanifest_$id.acf" ]; then
            if ui_confirm "🎮 Update Steam shortcut to point to restored prefix?"; then
                safe_vdf_edit "$sel" "$id"
            fi
        fi

        ui_header "✅ Restore Complete!"; sleep 1
    fi
}

function full_system_restore_logic() {
    source "$CONFIG_FILE"
    local rd="$SD_CARD_PATH/steamos_restore"
    [ ! -d "$rd" ] && return
    rsync -a "$rd/prefix_backups/" "$PREFIX_DIR/"
    [ -d "$rd/Syncthing/GameSaves" ] && rsync -a "$rd/Syncthing/GameSaves/" "$HOME/Syncthing/GameSaves/"
    [ -d "$rd/syncthing_config" ] && rsync -a "$rd/syncthing_config/" "$HOME/.config/syncthing/"
    cp -rT "$rd/scripts/" "$SCRIPTS_DIR/"
    chmod +x "$SCRIPTS_DIR"/*.sh
    systemctl --user daemon-reload
}

################################################################################
# SECTION 6: SETTINGS
################################################################################

function name_unnamed_games() {
    local found=false
    local officials=$(find "$STEAM_ROOT_DIR/steamapps" -name "appmanifest_*.acf" 2>/dev/null \
        | sed -E 's/.*appmanifest_([0-9]+)\.acf/\1/')

    for prefix_path in "$PREFIX_DIR"/*/; do
        [ -d "$prefix_path" ] || continue
        local id=$(basename "$prefix_path"); [ "$id" == "0" ] && continue
        echo "$officials" | grep -xq "$id" && continue
        grep -q "^$id," "$LOOKUP_FILE" && continue

        found=true
        local guess=$(get_name_from_shortcuts "$id")
        local prompt="Name for AppID $id"
        [ -n "$guess" ] && prompt="Name for AppID $id (suggested: $guess)"
        local name=$(ui_input "$prompt" "$guess")
        if [ -n "$name" ]; then
            local safe=$(echo "$name" | sed 's/[^a-zA-Z0-9._-]/_/g')
            echo "$id,$safe" >> "$LOOKUP_FILE"

            # Rename backup folder on SD card if it exists under old name
            source "$CONFIG_FILE" 2>/dev/null
            if [ -n "$SD_CARD_PATH" ] && [ -d "$SD_CARD_PATH" ]; then
                local backup_root="$SD_CARD_PATH/steamos_restore/prefix_backups"
                local old_folder=$(find "$backup_root" -mindepth 2 -maxdepth 2 \
                    -type d -name "$id" 2>/dev/null | head -n 1)
                if [ -n "$old_folder" ]; then
                    local old_parent=$(dirname "$old_folder")
                    local new_parent="$backup_root/$safe"
                    if [ "$old_parent" != "$new_parent" ]; then
                        mv "$old_parent" "$new_parent" 2>/dev/null && \
                            gum style --foreground 46 "📁 Backup folder renamed too."
                    fi
                fi
            fi

            gum style --foreground 46 "✅ Saved!"; sleep 0.5
        fi
    done

    [ "$found" = false ] && gum style --foreground 212 "No unnamed games found." && sleep 1
}

function configure_syncthing() {
    source "$CONFIG_FILE"
    ui_header "🔁 CONFIGURE SYNCTHING"
    local ak=$(ui_input "Enter Syncthing API Key" "${SYNCTHING_API_KEY:-}")
    local nid=$(ui_input "Enter NAS Device ID" "${SYNCTHING_NAS_ID:-}")
    local fid=$(ui_input "Enter Folder ID (e.g. steamos-saves)" "${SYNCTHING_FOLDER_ID:-}")

    sed -i "/^SYNCTHING_/d" "$CONFIG_FILE"
    echo "SYNCTHING_API_KEY=\"$ak\""   >> "$CONFIG_FILE"
    echo "SYNCTHING_NAS_ID=\"$nid\""   >> "$CONFIG_FILE"
    echo "SYNCTHING_FOLDER_ID=\"$fid\"" >> "$CONFIG_FILE"

    if ui_confirm "Attempt Auto-Configuration now?"; then
        local api="http://127.0.0.1:8384/rest/config"
        local lp="$HOME/Syncthing/GameSaves"; mkdir -p "$lp"
        gum spin --title "🔁 Configuring Syncthing..." -- sleep 2
        local pl="{\"id\":\"$fid\",\"label\":\"SteamOS Game Saves\",\"path\":\"$lp\",\"type\":\"sendreceive\",\"rescanIntervalS\":3600,\"autoNormalize\":true,\"versioning\":{\"type\":\"simple\",\"params\":{\"keep\":\"10\",\"cleanoutDays\":\"60\"}}}"
        curl -s -X POST -H "X-API-Key: $ak" "$api/folders" -d "$pl"
        curl -s -X POST -H "X-API-Key: $ak" "$api/devices" -d "{\"deviceID\":\"$nid\",\"name\":\"NAS\",\"autoAcceptFolders\":false,\"introducer\":false}"
        local cfg=$(curl -s -H "X-API-Key: $ak" "$api/folders/$fid")
        local new=$(echo "$cfg" | jq ".devices = (.devices // []) | if (.devices | map(.deviceID) | contains([\"$nid\"])) | not then .devices += [{\"deviceID\": \"$nid\"}] else . end")
        curl -s -X PUT -H "X-API-Key: $ak" "$api/folders/$fid" -d "$new"
        gum style --foreground 46 "✅ Configuration sent."; sleep 2
    fi
}

# Hidden — kept for future re-enabling
function manage_saves() {
    source "$CONFIG_FILE"
    ui_header "💿 MANAGE SAVE SYNC"
    local curr=$(get_scheduled_ids)
    local list=()
    for id in $curr; do
        local name=$(get_game_name "$id")
        list+=("$name ($id)")
    done

    if [ ${#list[@]} -eq 0 ]; then
        gum style --foreground 212 "No scheduled games to configure."; sleep 1; return
    fi

    local sel=$(printf '%s\n' "${list[@]}" | gum choose $GUM_OPTS --header "Select game to configure save sync")
    [ -z "$sel" ] && return

    local id=$(echo "$sel" | sed -E 's/.* \(([0-9]+)\)$/\1/')
    local name=$(echo "$sel" | sed -E 's/ \([0-9]+\)$//')

    ui_header "💿 SETUP: $name"
    echo " Opening prefix explorer and wiki..."
    xdg-open "$PREFIX_DIR/$id/pfx/drive_c" &>/dev/null
    xdg-open "https://www.pcgamingwiki.com/w/index.php?search=$name" &>/dev/null

    local path=$(ui_input "Paste path from drive_c (e.g. users/steamuser/AppData/...)")
    path=$(echo "$path" | tr '\\' '/')
    if [ ! -d "$PREFIX_DIR/$id/pfx/drive_c/$path" ]; then
        gum style --foreground 196 "❌ Path not found!"; sleep 2; return
    fi

    local repo=$(ui_input "Enter Repo Name (no spaces)")
    sed -i "/^$id,/d" "$SAVE_SYNC_MAP_FILE"
    echo "$id,$PREFIX_DIR/$id/pfx/drive_c/$path,$HOME/Syncthing/GameSaves/$repo" >> "$SAVE_SYNC_MAP_FILE"
    mkdir -p "$HOME/Syncthing/GameSaves/$repo"

    clear
    gum style --border double --padding "1 2" --foreground 212 "📋 COPY THIS LAUNCH OPTION:"
    local old=$(get_launch_options_hack "$id")
    old=$(echo "$old" | sed -E "s|$SAVE_WRAPPER_SCRIPT $id %command% *||")
    echo "$SAVE_WRAPPER_SCRIPT $id %command% $old"
    read -p "Press Enter when done."
    if ui_confirm "Restart Steam now?"; then killall -TERM steam; fi
}

################################################################################
# SECTION 7: MENU LOOPS
################################################################################

function menu_backup() {
    while true; do
        ui_header "💾 BACKUP"
        local opt=$(ui_choose "What would you like to do?" \
            "📋 Manage Schedule" \
            "▶️  Run Backup Now" \
            "📸 Create Restore Point" \
            "⬅️  Back")
        case "$opt" in
            "📋 Manage Schedule")      manage_backup_schedule ;;
            "▶️  Run Backup Now")       manual_backup ;;
            "📸 Create Restore Point") create_restore_point ;;
            "⬅️  Back"|"") return ;;
        esac
    done
}

function menu_restore() {
    while true; do
        ui_header "🔄 RESTORE"
        local opt=$(ui_choose "What would you like to restore?" \
            "🎮 Restore a Game" \
            "🔍 Find a Prefix" \
            "♻️  Full System Restore" \
            "⬅️  Back")
        case "$opt" in
            "🎮 Restore a Game") restore_single_game ;;
            "🔍 Find a Prefix") find_prefix ;;
            "♻️  Full System Restore")
                if ui_confirm_danger "This will overwrite ALL current prefixes, scripts and Syncthing config from the SD card."; then
                    ui_header "♻️  RESTORING SYSTEM..."
                    full_system_restore_logic
                    ui_header "✅ System Restored!"; sleep 2
                fi ;;
            "⬅️  Back"|"") return ;;
        esac
    done
}

function menu_settings() {
    while true; do
        ui_header "⚙️  SETTINGS"
        local opt=$(ui_choose "What would you like to configure?" \
            "💳 SD Card Path" \
            "🏷️  Name Unknown Games" \
            "🔁 Configure Syncthing" \
            "⬅️  Back")
        case "$opt" in
            "💳 SD Card Path")
                gum spin --title "🔍 Detecting SD cards..." -- sleep 1
                local detected=$(detect_sd_card)
                if [ -n "$detected" ]; then
                    if ui_confirm "Use $(basename "$detected")?"; then
                        sed -i "s|SD_CARD_PATH=.*|SD_CARD_PATH=\"$detected\"|" "$CONFIG_FILE"
                        gum style --foreground 46 "✅ Saved!"; sleep 1
                        continue
                    fi
                fi
                local p=$(ui_input "Enter SD Card name manually (e.g. primary)")
                if [ -n "$p" ]; then
                    sed -i "s|SD_CARD_PATH=.*|SD_CARD_PATH=\"/run/media/deck/$p\"|" "$CONFIG_FILE"
                    gum style --foreground 46 "✅ Saved!"; sleep 1
                fi ;;
            "🏷️  Name Unknown Games") name_unnamed_games ;;
            "🔁 Configure Syncthing") configure_syncthing ;;
            "⬅️  Back"|"") return ;;
        esac
    done
}

function check_for_update() {
    local remote_url="https://raw.githubusercontent.com/TPepperoni666/Bazzite-Tools/main/Scripts/SteamOS-Prefix-Manager/steamos_manager.sh"
    ui_header "⬆️  CHECK FOR UPDATE"
    gum style --foreground 250 "  🌐 Checking for updates..."

    local tmp_file
    tmp_file=$(mktemp /tmp/steamos_manager_update.XXXXXX)

    if ! curl -fsSL "$remote_url" -o "$tmp_file" 2>/dev/null; then
        gum style --foreground 212 "⚠️  Could not reach GitHub. Check your internet connection."
        rm -f "$tmp_file"
        sleep 3
        return
    fi

    local local_ver remote_ver
    local_ver=$(grep -m1 '^# === SteamOS Backup Manager' "$MANAGER_SCRIPT_PATH" | grep -oP 'v[\d.]+')
    remote_ver=$(grep -m1 '^# === SteamOS Backup Manager' "$tmp_file" | grep -oP 'v[\d.]+')

    if [ "$local_ver" = "$remote_ver" ] && [ -n "$local_ver" ]; then
        gum style --foreground 46 "✅ Already up to date ($local_ver)."
        rm -f "$tmp_file"
        sleep 2
        return
    fi

    local label="${local_ver:-unknown} → ${remote_ver:-unknown}"
    if [ -z "$remote_ver" ]; then
        label="(version unknown — update anyway?)"
    fi

    if ui_confirm "Update available: $label. Install now?"; then
        cp "$tmp_file" "$MANAGER_SCRIPT_PATH"
        chmod +x "$MANAGER_SCRIPT_PATH"
        rm -f "$tmp_file"
        gum style --foreground 46 "✅ Updated! Restarting..."
        sleep 2
        exec bash "$MANAGER_SCRIPT_PATH"
    else
        gum style --foreground 250 "  Update skipped."
        rm -f "$tmp_file"
        sleep 1
    fi
}

################################################################################
# SECTION 8: MAIN EXECUTION
################################################################################

check_dependencies

if [ ! -f "$CONFIG_FILE" ]; then
    ui_header "🎮 FIRST TIME SETUP"

    gum spin --title "🔍 Detecting SD card..." -- sleep 1
    path=$(detect_sd_card)

    if [ -z "$path" ]; then
        gum style --foreground 212 "⚠️  No SD card detected. You can set it later in ⚙️  Settings."
        path=""
    else
        gum style --foreground 46 "✅ Found: $(basename "$path")"; sleep 1
    fi

    mkdir -p "$SCRIPTS_DIR" "$SYSTEMD_DIR"
    echo "SD_CARD_PATH=\"$path\"" > "$CONFIG_FILE"
    touch "$LOOKUP_FILE" "$LOG_FILE" "$SAVE_SYNC_MAP_FILE"
    update_helper_scripts
    install_systemd_files
    install_desktop_shortcut
    systemctl --user enable --now steamos-prefix-backup.timer
    gum style --foreground 46 "✅ Setup Complete!"; sleep 2
fi

update_helper_scripts

while true; do
    source "$CONFIG_FILE"
    last=$(grep "SUCCESS" "$LOG_FILE" 2>/dev/null | head -n 1 | sed 's/.*] //')
    count=$(get_scheduled_count)

    clear
    gum style \
        --foreground 99 --border-foreground 99 --border double \
        --padding "0 2" --align center --width 60 \
        "💾 STEAMOS BACKUP MANAGER"
    echo ""
    gum style --foreground 250 "  💳 Target : ${SD_CARD_PATH:-Not set}"
    gum style --foreground 250 "  🎮 Games  : $count scheduled"
    gum style --foreground 250 "  🕐 Last   : ${last:-Never}"
    echo ""

    OPT=$(gum choose $GUM_OPTS \
        "💾 Backup" \
        "🔄 Restore" \
        "⚙️  Settings" \
        "⬆️  Check for Update" \
        "❌ Exit")

    case "$OPT" in
        "💾 Backup")             menu_backup ;;
        "🔄 Restore")            menu_restore ;;
        "⚙️  Settings")          menu_settings ;;
        "⬆️  Check for Update")  check_for_update ;;
        "❌ Exit"|"")            clear; exit 0 ;;
    esac
done
