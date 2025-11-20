#!/bin/bash
# P13: Simple Hex Aspect Ratio Patcher 📐
# Hex-Edits Game EXEs to support 16:10 (Deck/Legion) or Ultrawide.

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

# --- Hex Constants (Little Endian Float) ---
# 16:9 (1.777) - The most common default
HEX_16_9="\x39\x8E\xE3\x3F"

# Targets
HEX_16_10="\xCD\xCC\xCC\x3F"  # 1.600 (Steam Deck / Legion Go)
HEX_21_9="\x8E\xE3\x18\x40"   # 2.388 (Standard Ultrawide 3440/1440)
HEX_32_9="\x39\x8E\x63\x40"   # 3.555 (Super Ultrawide)

# --- Helper: Patcher ---
apply_patch() {
    FILE_PATH=$1
    TARGET_RATIO=$2
    TARGET_HEX=$3

    # 1. Create Backup
    if [ ! -f "$FILE_PATH.bak" ]; then
        $GUM style --foreground 212 "💾 Creating backup: $FILE_PATH.bak"
        cp "$FILE_PATH" "$FILE_PATH.bak"
    else
        $GUM style --foreground 240 "ℹ️  Backup already exists."
    fi

    # 2. Check if file actually contains the 16:9 value
    if ! grep -Pq "$HEX_16_9" "$FILE_PATH"; then
        $GUM style --foreground 196 "⚠️  Error: Could not find standard 16:9 hex code."
        echo "This game might calculate aspect ratio differently."
        if ! $GUM confirm "Force patch anyway? (Risky)"; then
            return
        fi
    fi

    # 3. Apply Patch using Perl (In-place edit)
    $GUM style --foreground 212 "🔨 Patching to $TARGET_RATIO..."
    perl -pi -e "s/$HEX_16_9/$TARGET_HEX/g" "$FILE_PATH"

    if [ $? -eq 0 ]; then
        $GUM style --foreground 120 "✅ Patch Applied Successfully!"
        echo "---------------------------------------------------"
        echo "💡 TIP: If the game looks 'Zoomed In' (Vert- Scaling):"
        echo "1. Try increasing the FOV in the game's video settings."
        echo "2. If that fails, restore the backup and use P3 (Mod Helper)"
        echo "   to install Flawless Widescreen via SteamTinkerLaunch."
        echo "---------------------------------------------------"
    else
        $GUM style --foreground 196 "❌ Patch Failed."
    fi
    
    read -p "Press Enter to continue..."
}

# --- Helper: Restore ---
restore_backup() {
    FILE_PATH=$1
    if [ -f "$FILE_PATH.bak" ]; then
        mv "$FILE_PATH.bak" "$FILE_PATH"
        $GUM style --foreground 120 "✅ Backup Restored."
    else
        $GUM style --foreground 196 "❌ No backup found for this file."
    fi
    sleep 1
}

# --- Main Menu ---
show_patcher_menu() {
    clear
    $GUM style --border double --margin "1" --padding "1" --border-foreground 99 --foreground 99 "📐 Simple Hex Aspect Ratio Patcher" "   [ 16:10 | 21:9 | 32:9 ]"

    echo "Select the Game Executable (.exe) to patch:"
    EXE_PATH=$($GUM file "$HOME/.local/share/Steam/steamapps/common")

    if [ -z "$EXE_PATH" ]; then return; fi

    FILENAME=$(basename "$EXE_PATH")

    ACTION=$($GUM choose --header "Action for: $FILENAME" \
        "📱 Patch to 16:10 (Steam Deck / Legion Go)" \
        "🖥️  Patch to 21:9 (Ultrawide)" \
        "🛣️  Patch to 32:9 (Super Ultrawide)" \
        "🔙 Restore Backup (.bak)" \
        "CANCEL")

    case "$ACTION" in
        "📱 Patch to 16:10"*)
            apply_patch "$EXE_PATH" "16:10" "$HEX_16_10" ;;
        "🖥️  Patch to 21:9"*)
            apply_patch "$EXE_PATH" "21:9" "$HEX_21_9" ;;
        "🛣️  Patch to 32:9"*)
            apply_patch "$EXE_PATH" "32:9" "$HEX_32_9" ;;
        "🔙 Restore Backup"*)
            restore_backup "$EXE_PATH" ;;
        *) return ;;
    esac
    
    show_patcher_menu
}

show_patcher_menu
