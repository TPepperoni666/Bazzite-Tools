#!/bin/bash
# P10: Boot & Sleep Video Swapper
# Uses 'gum' passed from the main hub

GUM=$1
if [ -z "$GUM" ]; then GUM="gum"; fi

DOWNLOADS_DIR="$HOME/Downloads"
BOOT_VIDEO_PATH="$HOME/.local/share/Steam/config/uioverrides/movies"

show_video_menu() {
    # 1. Scan for .webm files
    FILES=$(find "$DOWNLOADS_DIR" -maxdepth 1 -name "*.webm" -printf "%f\n")

    if [ -z "$FILES" ]; then
        $GUM style --foreground 196 "⚠️  No .webm files found in $DOWNLOADS_DIR"
        $GUM confirm "Return to Menu?" && return || return
    fi

    # 2. Select a File
    SELECTED_FILE=$($GUM choose --header "Select a video file:" $FILES "CANCEL")

    if [ "$SELECTED_FILE" == "CANCEL" ]; then return; fi

    # 3. Select Target
    TARGET=$($GUM choose --header "Set '$SELECTED_FILE' as:" \
        "Boot Video (deck_startup.webm)" \
        "Suspend Video (deck_suspend.webm)" \
        "Throbber (deck-throbber.webm)")

    # 4. Map selection to filename
    case "$TARGET" in
        "Boot Video"*) TARGET_NAME="deck_startup.webm" ;;
        "Suspend Video"*) TARGET_NAME="deck_suspend.webm" ;;
        "Throbber"*) TARGET_NAME="deck_throbber.webm" ;;
        *) return ;;
    esac

    # 5. Execute (Create folder if missing)
    mkdir -p "$BOOT_VIDEO_PATH"
    cp "$DOWNLOADS_DIR/$SELECTED_FILE" "$BOOT_VIDEO_PATH/$TARGET_NAME"

    $GUM style --foreground 120 "✅ Successfully set $TARGET_NAME!"
    sleep 2
}

show_video_menu
