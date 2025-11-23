#!/bin/bash

# Monitor USB keyboard connection and control display input
# Service script for USB-HID device monitoring

KEYBOARD_NAME="USB-HID Keyboard"
DEVICE="/dev/i2c-12"
CHECK_INTERVAL=2       # seconds between checks
INPUT_DISCONNECTED=18  # HDMI input for laptop (keyboard disconnected)
INPUT_CONNECTED=16     # DisplayPort input for this machine (keyboard connected)

# State file to track previous connection status
STATE_FILE="/tmp/keyboard-monitor-state"

# Initialize state file if it doesn't exist
if [ ! -f "$STATE_FILE" ]; then
    echo "unknown" > "$STATE_FILE"
fi

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

is_keyboard_connected() {
    # Check if the keyboard is present in USB devices
    lsusb | grep -q "$KEYBOARD_NAME"
    return $?
}

switch_to_input_17() {
    log_message "Keyboard disconnected - switching to input $INPUT_DISCONNECTED"
    ddccontrol -r 0x60 -w $INPUT_DISCONNECTED dev:${DEVICE}
}

switch_to_input_16() {
    log_message "Keyboard connected - switching to input $INPUT_CONNECTED"
    ddccontrol -r 0x60 -w $INPUT_CONNECTED dev:${DEVICE}
}

log_message "Starting keyboard monitor service"

while true; do
    PREVIOUS_STATE=$(cat "$STATE_FILE")
    
    if is_keyboard_connected; then
        CURRENT_STATE="connected"
    else
        CURRENT_STATE="disconnected"
    fi
    
    # Only act on state changes
    if [ "$CURRENT_STATE" != "$PREVIOUS_STATE" ]; then
        if [ "$CURRENT_STATE" = "connected" ]; then
            switch_to_input_16
        else
            switch_to_input_17
        fi
        echo "$CURRENT_STATE" > "$STATE_FILE"
    fi
    
    sleep $CHECK_INTERVAL
done
