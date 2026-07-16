import Carbon.HIToolbox
import CoreGraphics
import Foundation
import PD200XTarget

enum KeyboardEventError: Error, LocalizedError {
    case permissionRequired
    case unsupportedKey(String)
    case eventCreationFailed

    var errorDescription: String? {
        switch self {
        case .permissionRequired:
            return "Keyboard Control permission is required. Open Settings and grant it to PD200X Button."
        case let .unsupportedKey(key):
            return "The key “\(key)” is not supported."
        case .eventCreationFailed:
            return "macOS could not create the keyboard event."
        }
    }
}

final class KeyboardEventPoster {
    static var hasPermission: Bool {
        CGPreflightPostEventAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestPostEventAccess()
    }

    func post(_ shortcut: KeyboardShortcut) throws {
        guard Self.hasPermission else { throw KeyboardEventError.permissionRequired }
        guard let keyCode = keyCode(for: shortcut.key) else {
            throw KeyboardEventError.unsupportedKey(shortcut.key)
        }

        if shortcut.pressCount > 1,
           shortcut.modifiers.isEmpty,
           let modifierFlag = modifierFlag(forKey: shortcut.key) {
            for index in 0..<shortcut.pressCount {
                try postKey(keyCode, flags: modifierFlag)
                if index + 1 < shortcut.pressCount {
                    Thread.sleep(forTimeInterval: 0.12)
                }
            }
            return
        }

        let flags = shortcut.modifiers.reduce(into: CGEventFlags()) {
            $0.formUnion(flag(for: $1))
        }
        for index in 0..<shortcut.pressCount {
            try postKey(keyCode, flags: flags)
            if index + 1 < shortcut.pressCount {
                Thread.sleep(forTimeInterval: 0.12)
            }
        }
    }

    func pressEnter() throws {
        try post(KeyboardShortcut(key: "return"))
    }

    func pressEscape() throws {
        try post(KeyboardShortcut(key: "escape"))
    }

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) throws {
        guard let down = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: true
        ), let up = CGEvent(
            keyboardEventSource: nil,
            virtualKey: keyCode,
            keyDown: false
        ) else {
            throw KeyboardEventError.eventCreationFailed
        }

        down.flags = flags
        up.flags = []
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.035)
        up.post(tap: .cghidEventTap)
    }

    private func flag(for modifier: KeyModifier) -> CGEventFlags {
        switch modifier {
        case .command: return .maskCommand
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .shift: return .maskShift
        case .function: return .maskSecondaryFn
        }
    }

    private func modifierFlag(forKey key: String) -> CGEventFlags? {
        switch key {
        case "command", "cmd": return .maskCommand
        case "option", "opt", "alt": return .maskAlternate
        case "control", "ctrl": return .maskControl
        case "shift": return .maskShift
        case "fn", "function": return .maskSecondaryFn
        default: return nil
        }
    }

    private func keyCode(for rawKey: String) -> CGKeyCode? {
        switch rawKey.lowercased() {
        case "a": return CGKeyCode(kVK_ANSI_A)
        case "b": return CGKeyCode(kVK_ANSI_B)
        case "c": return CGKeyCode(kVK_ANSI_C)
        case "d": return CGKeyCode(kVK_ANSI_D)
        case "e": return CGKeyCode(kVK_ANSI_E)
        case "f": return CGKeyCode(kVK_ANSI_F)
        case "g": return CGKeyCode(kVK_ANSI_G)
        case "h": return CGKeyCode(kVK_ANSI_H)
        case "i": return CGKeyCode(kVK_ANSI_I)
        case "j": return CGKeyCode(kVK_ANSI_J)
        case "k": return CGKeyCode(kVK_ANSI_K)
        case "l": return CGKeyCode(kVK_ANSI_L)
        case "m": return CGKeyCode(kVK_ANSI_M)
        case "n": return CGKeyCode(kVK_ANSI_N)
        case "o": return CGKeyCode(kVK_ANSI_O)
        case "p": return CGKeyCode(kVK_ANSI_P)
        case "q": return CGKeyCode(kVK_ANSI_Q)
        case "r": return CGKeyCode(kVK_ANSI_R)
        case "s": return CGKeyCode(kVK_ANSI_S)
        case "t": return CGKeyCode(kVK_ANSI_T)
        case "u": return CGKeyCode(kVK_ANSI_U)
        case "v": return CGKeyCode(kVK_ANSI_V)
        case "w": return CGKeyCode(kVK_ANSI_W)
        case "x": return CGKeyCode(kVK_ANSI_X)
        case "y": return CGKeyCode(kVK_ANSI_Y)
        case "z": return CGKeyCode(kVK_ANSI_Z)
        case "0": return CGKeyCode(kVK_ANSI_0)
        case "1": return CGKeyCode(kVK_ANSI_1)
        case "2": return CGKeyCode(kVK_ANSI_2)
        case "3": return CGKeyCode(kVK_ANSI_3)
        case "4": return CGKeyCode(kVK_ANSI_4)
        case "5": return CGKeyCode(kVK_ANSI_5)
        case "6": return CGKeyCode(kVK_ANSI_6)
        case "7": return CGKeyCode(kVK_ANSI_7)
        case "8": return CGKeyCode(kVK_ANSI_8)
        case "9": return CGKeyCode(kVK_ANSI_9)
        case "space": return CGKeyCode(kVK_Space)
        case "return", "enter": return CGKeyCode(kVK_Return)
        case "escape", "esc": return CGKeyCode(kVK_Escape)
        case "tab": return CGKeyCode(kVK_Tab)
        case "left": return CGKeyCode(kVK_LeftArrow)
        case "right": return CGKeyCode(kVK_RightArrow)
        case "up": return CGKeyCode(kVK_UpArrow)
        case "down": return CGKeyCode(kVK_DownArrow)
        case "command", "cmd": return CGKeyCode(kVK_Command)
        case "option", "opt", "alt": return CGKeyCode(kVK_Option)
        case "control", "ctrl": return CGKeyCode(kVK_Control)
        case "shift": return CGKeyCode(kVK_Shift)
        case "fn", "function": return CGKeyCode(kVK_Function)
        default: return nil
        }
    }
}
