#!/bin/zsh
set -euo pipefail

app_path="$HOME/Applications/PD200X Button.app"
marker_path="$app_path/Contents/Resources/pd200x-button-owned"
legacy_marker_path="$app_path/Contents/Resources/pd200x-prototype-owned"
launch_agent="$HOME/Library/LaunchAgents/com.maulik.pd200x-button.plist"
launch_domain="gui/$(id -u)"

launchctl bootout "$launch_domain/com.maulik.pd200x-button" 2>/dev/null || true
pkill -f "$app_path/Contents/MacOS/pd200x-button-helper" 2>/dev/null || true
pkill -f "$app_path/Contents/MacOS/PD200XButtonMenu" 2>/dev/null || true
rm -f "$launch_agent"

if [[ -d "$app_path" ]]; then
    if [[ ! -f "$marker_path" && ! -f "$legacy_marker_path" ]]; then
        print -u2 "Refusing to remove an app that was not created by this installer: $app_path"
        exit 1
    fi
    rm -rf "$app_path"
fi

defaults delete com.maulik.pd200x-button 2>/dev/null || true
print "Removed the PD200X menu bar app. The microphone button now uses its original function."
