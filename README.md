# PD200X Button

A small, reversible macOS menu bar app that turns the physical mute button on a Maono PD200X microphone into a configurable dictation control.

One press starts dictation. The next press stops dictation and can press Enter after a configurable delay. When you switch to Meeting mode, the helper stops and the microphone button immediately returns to its normal hardware mute behavior.

[Read the visual guide](https://lazzyms.github.io/pd200x-button/)

## Features

- Manual Dictation and Meeting modes. There is no automatic meeting detection.
- Handy support through its supported `--toggle-transcription` and `--cancel` commands.
- Native macOS Dictation support using the shortcut configured in Keyboard settings.
- Custom start and stop shortcuts for other dictation applications.
- Optional Enter submission with an adjustable delay from zero to ten seconds.
- A menu bar settings window. No configuration files need to be edited.
- A Start at Login toggle that persists across reboots.
- A guarded Human Interface Device implementation that only reads mute state and sends the known force-unmute packet.
- A complete uninstaller that restores the original button behavior.

## How it works

The hardware helper has one narrow responsibility. It watches the PD200X mute state, restores the microphone to unmuted in Dictation mode, and reports a physical button press to the menu app.

The menu app owns the selected target and session state. It turns each press into one of three actions:

1. Handy runs its remote toggle command.
2. macOS Dictation receives the configured double-modifier shortcut.
3. A custom target receives user-defined start and stop shortcuts in the currently active application.

On the stopping press, the app optionally waits for transcription to finish and sends Enter. Keyboard shortcuts and Enter require macOS permission to post keyboard events. The Settings window can request that permission.

Apple documents starting and stopping Dictation with its configured keyboard shortcut in the [macOS User Guide](https://support.apple.com/guide/mac-help/use-dictation-mh40584/mac). Handy documents its command-line remote controls in the [official Handy repository](https://github.com/cjpais/handy).

## Requirements

- macOS 13 Ventura or newer.
- A Maono PD200X microphone with USB vendor identifier `13615` and product identifier `260`.
- Swift 5.9 or newer to build from source.
- Handy is optional and only required when Handy is the selected target.

The Human Interface Device packets are deliberately allow-listed for this exact device. Other microphones are not supported without a separate, verified protocol profile.

## Install

Download the latest macOS installer package from GitHub Pages:

- https://lazzyms.github.io/pd200x-button/downloads/pd200x-button-macos-latest.pkg

The package is currently unsigned and not notarized. On first install, macOS may show a warning and require opening the package from the context menu.

Or build and install from source:

Clone the repository and run the installer:

```sh
git clone https://github.com/lazzyms/pd200x-button.git
cd pd200x-button
./Scripts/build-and-install.sh
```

The script runs the test suite, creates a release build, installs `PD200X Button.app` in your user Applications folder, signs it locally, and starts its login agent. If an Apple Development signing identity is available in Keychain, the installer uses it so Accessibility permission survives rebuilds. Otherwise it uses ad hoc signing and warns that permission may need to be granted again after updates. Set `PD200X_SIGNING_IDENTITY` to choose a specific identity.

The menu bar title shows `Dictate` or `Meeting`. Open the menu, choose Settings, and select Handy, macOS Dictation, or Custom Shortcut. If Enter submission or keyboard shortcuts are enabled, use Request Access once and approve the macOS prompt.

## Update

Pull the latest source and run the same installer again:

```sh
git pull
./Scripts/build-and-install.sh
```

The selected mode and target settings are preserved.

## Release packaging and publishing

Tagged releases (`v*`) run `.github/workflows/publish-macos-installer.yml` on macOS to:

1. run `swift test` and `swift build -c release`,
2. build `PD200X Button.app`,
3. package it as an unsigned `.pkg`,
4. publish the stable download artifact to `docs/downloads/pd200x-button-macos-latest.pkg` (plus a `.sha256` checksum) for GitHub Pages.

## Restore the original button

For a temporary reset, select Meeting Mode. The helper stops completely and the microphone firmware controls the mute button.

For a complete removal, run:

```sh
./Scripts/uninstall.sh
```

The uninstaller stops the login service, removes only the app bundle created by this project, clears its saved preferences, and leaves the microphone with its original firmware behavior.

## Development

Run all transition and target-planning tests with:

```sh
swift test
```

The package is split into three modules. `PD200XButtonProbe` owns the guarded hardware protocol. `PD200XTarget` turns configuration and session state into actions. `PD200XButtonMenu` owns the user interface, target execution, and keyboard-event permission.

## Safety boundary

The microphone protocol is not a standard Core Audio mute property. The helper uses the same single-property query observed for mute state and one exact force-unmute packet. Byte-for-byte guards reject every other outbound packet. The app does not flash firmware, seize the audio interface, or send a force-mute command.

Use this project at your own risk. Keep Meeting mode and the uninstaller available before experimenting with hardware changes.
