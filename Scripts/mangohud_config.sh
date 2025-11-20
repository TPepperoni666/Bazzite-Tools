#!/bin/bash
# P7: MangoHud Configurator 
# Allows changing MangoHud Layout, Scaling, and Transparency via TUI.

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

CONFIG_DIR="$HOME/.config/MangoHud"
CONFIG_FILE="$CONFIG_DIR/MangoHud.conf"
BACKUP_FILE="$CONFIG_DIR/MangoHud.conf.bak"

# --- 1. Initialization & Backup ---
ensure_config() {
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
    fi
    
    # If config doesn't exist, create a standard default
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "legacy_layout=0" > "$CONFIG_FILE"
        echo "hud_scale=1.0" >> "$CONFIG_FILE"
        echo "table_columns=3" >> "$CONFIG_FILE"
        echo "background_alpha=0.5" >> "$CONFIG_FILE"
        echo "gpu_stats" >> "$CONFIG_FILE"
        echo "cpu_stats" >> "$CONFIG_FILE"
        echo "fps" >> "$CONFIG_FILE"
        echo "frame_timing" >> "$CONFIG_FILE"
    fi

    # Create backup if it doesn't exist
    if [ ! -f "$BACKUP_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
    fi
}

# --- 2. Helper: Update Key in Config ---
# Usage: update_conf "key" "value"
update_conf() {
    local key=$1
    local value=$2
    
    if grep -q "^$key" "$CONFIG_FILE"; then
        # Key exists, replace it (handling potential spaces)
        sed -i "s|^$key.*|$key=$value|" "$CONFIG_FILE"
    else
        # Key doesn't exist, append it
        echo "$key=$value" >> "$CONFIG_FILE"
    fi
}

# --- 3. Feature: Set Layouts ---
apply_layout() {
    local type=$1
    
    case "$type" in
        "vertical")
            update_conf "legacy_layout" "0"
            update_conf "table_columns" "3"
            update_conf "cell_padding" "0"
            update_conf "hud_compact" "0"
            # Remove horizontal specific overrides if they exist
            sed -i "/^position=/d" "$CONFIG_FILE" 
            ;;
        "horizontal")
            # The "Legion Bar" style (top of screen strip)
            update_conf "legacy_layout" "0"
            update_conf "table_columns" "24"
            update_conf "cell_padding" "2"
            update_conf "hud_compact" "1"
            update_conf "position" "top-left"
            ;;
    esac
}

# --- 4. Main Menu ---
show_osd_menu() {
    ensure_config
    
    # Grab current scale for display
    CURRENT_SCALE=$(grep "^hud_scale" "$CONFIG_FILE" | cut -d'=' -f2)
    if [ -z "$CURRENT_SCALE" ]; then CURRENT_SCALE="1.0"; fi

    clear
    $GUM style --border double --margin "1" --padding "1" --border-foreground 99 --foreground 99 "🎨 MangoHud Configurator" "   Current Scale: $CURRENT_SCALE"

    CHOICE=$($GUM choose \
        "📏  Change HUD Scale (Text Size)" \
        "🖼️   Change Layout (Vertical vs Horizontal)" \
        "👻  Toggle Background Transparency" \
        "🔙  Restore Backup Config" \
        "EXIT")

    case "$CHOICE" in
        "📏  Change HUD Scale"*)
            NEW_SCALE=$($GUM choose "1.0 (Deck Default)" "1.2" "1.5 (Legion Go/Ally)" "1.8" "2.0 (Huge)")
            # Extract just the number
            VAL=$(echo "$NEW_SCALE" | cut -d' ' -f1)
            update_conf "hud_scale" "$VAL"
            $GUM style --foreground 120 "✅ Scale set to $VAL"
            sleep 1
            ;;
            
        "🖼️   Change Layout"*)
            LAYOUT=$($GUM choose "📱 Vertical (Classic)" "➖ Horizontal (Top Bar)")
            if [[ "$LAYOUT" == *"Vertical"* ]]; then
                apply_layout "vertical"
                $GUM style --foreground 120 "✅ Set to Vertical Layout"
            else
                apply_layout "horizontal"
                $GUM style --foreground 120 "✅ Set to Horizontal Bar"
            fi
            sleep 1
            ;;
            
        "👻  Toggle Background Transparency"*)
            ALPHA=$($GUM choose "0.0 (Invisible)" "0.4 (Semi-Transparent)" "0.8 (Dark)" "1.0 (Solid Black)")
            VAL=$(echo "$ALPHA" | cut -d' ' -f1)
            update_conf "background_alpha" "$VAL"
            $GUM style --foreground 120 "✅ Opacity set to $VAL"
            sleep 1
            ;;

        "🔙  Restore Backup Config"*)
            if [ -f "$BACKUP_FILE" ]; then
                if $GUM confirm "Overwrite current config with backup?"; then
                    cp "$BACKUP_FILE" "$CONFIG_FILE"
                    $GUM style --foreground 120 "✅ Backup Restored."
                    sleep 1
                fi
            else
                $GUM style --foreground 196 "❌ No backup found."
                sleep 2
            fi
            ;;

        "EXIT") return ;;
    esac
    
    show_osd_menu
}

show_osd_menu
