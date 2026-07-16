#!/bin/zsh
set -euo pipefail

root_dir="${0:A:h:h}"
app_path="$HOME/Applications/PD200X Button.app"
marker_path="$app_path/Contents/Resources/pd200x-button-owned"
legacy_marker_path="$app_path/Contents/Resources/pd200x-prototype-owned"
launch_agent="$HOME/Library/LaunchAgents/com.maulik.pd200x-button.plist"
launch_domain="gui/$(id -u)"
menu_executable="$app_path/Contents/MacOS/PD200XButtonMenu"

cd "$root_dir"
swift test
swift build -c release

if [[ -e "$app_path" && ! -f "$marker_path" && ! -f "$legacy_marker_path" ]]; then
    print -u2 "Refusing to replace an app that was not created by this installer: $app_path"
    exit 1
fi

launchctl bootout "$launch_domain/com.maulik.pd200x-button" 2>/dev/null || true
pkill -f "$app_path/Contents/MacOS/pd200x-button-helper" 2>/dev/null || true
pkill -f "$app_path/Contents/MacOS/PD200XButtonMenu" 2>/dev/null || true

if [[ -d "$app_path" ]]; then
    rm -rf "$app_path"
fi

mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$root_dir/Packaging/Info.plist" "$app_path/Contents/Info.plist"
cp "$root_dir/Packaging/pd200x-button-owned" "$marker_path"
cp "$root_dir/.build/release/PD200XButtonMenu" "$app_path/Contents/MacOS/PD200XButtonMenu"
cp "$root_dir/.build/release/pd200x-button-probe" "$app_path/Contents/MacOS/pd200x-button-helper"
chmod 755 "$app_path/Contents/MacOS/PD200XButtonMenu" "$app_path/Contents/MacOS/pd200x-button-helper"
codesign --force --deep --sign - "$app_path"

mkdir -p "$HOME/Library/LaunchAgents"
"$menu_executable" --install-login-agent
plutil -lint "$app_path/Contents/Info.plist" "$launch_agent"
launchctl bootstrap "$launch_domain" "$launch_agent"

print "Installed and started: $app_path"
