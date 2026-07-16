import Foundation

public enum DictationTargetKind: String, Codable, CaseIterable {
    case handy
    case macOSDictation
    case customShortcut

    public var displayName: String {
        switch self {
        case .handy: return "Handy"
        case .macOSDictation: return "macOS Dictation"
        case .customShortcut: return "Custom Shortcut"
        }
    }
}

public enum KeyModifier: String, Codable, CaseIterable, Hashable {
    case command
    case option
    case control
    case shift
    case function
}

public struct KeyboardShortcut: Codable, Equatable {
    public let key: String
    public let modifiers: [KeyModifier]
    public let pressCount: Int

    public init(key: String, modifiers: [KeyModifier] = [], pressCount: Int = 1) {
        self.key = key
        self.modifiers = modifiers
        self.pressCount = max(1, pressCount)
    }

    public static func parse(_ rawValue: String) throws -> KeyboardShortcut {
        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "⌘", with: "command")
            .replacingOccurrences(of: "⌥", with: "option")
            .replacingOccurrences(of: "⌃", with: "control")
            .replacingOccurrences(of: "⇧", with: "shift")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let repeatedParts = normalized
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        if repeatedParts.count == 2,
           repeatedParts[0] == repeatedParts[1],
           modifier(named: repeatedParts[0]) != nil {
            return KeyboardShortcut(key: repeatedParts[0], pressCount: 2)
        }

        let parts = normalized
            .split(separator: "+")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let key = parts.last, isSupportedKey(key) else {
            throw ShortcutError.invalid(rawValue)
        }

        let modifiers = try parts.dropLast().map { part in
            guard let modifier = modifier(named: part) else {
                throw ShortcutError.invalid(rawValue)
            }
            return modifier
        }
        return KeyboardShortcut(key: key, modifiers: modifiers)
    }

    public var displayName: String {
        if pressCount == 2, modifiers.isEmpty {
            return "\(key.capitalized) twice"
        }
        return (modifiers.map(\.rawValue) + [key])
            .map(\.capitalized)
            .joined(separator: " + ")
    }

    private static func modifier(named value: String) -> KeyModifier? {
        switch value {
        case "cmd", "command": return .command
        case "opt", "alt", "option": return .option
        case "ctrl", "control": return .control
        case "shift": return .shift
        case "fn", "function": return .function
        default: return nil
        }
    }

    private static func isSupportedKey(_ key: String) -> Bool {
        if key.count == 1,
           key.range(of: "[a-z0-9]", options: .regularExpression) != nil {
            return true
        }
        return [
            "space", "return", "enter", "escape", "esc", "tab",
            "up", "down", "left", "right", "fn", "function",
            "command", "cmd", "option", "opt", "alt", "control",
            "ctrl", "shift",
        ].contains(key)
    }
}

public enum ShortcutError: Error, LocalizedError, Equatable {
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case let .invalid(value):
            return "“\(value)” is not a supported shortcut. Try command+shift+d or control control."
        }
    }
}

public enum NativeDictationShortcut: String, Codable, CaseIterable {
    case functionTwice
    case controlTwice
    case optionTwice
    case commandTwice

    public var displayName: String {
        switch self {
        case .functionTwice: return "Function key twice"
        case .controlTwice: return "Control key twice"
        case .optionTwice: return "Option key twice"
        case .commandTwice: return "Command key twice"
        }
    }

    public var shortcut: KeyboardShortcut {
        switch self {
        case .functionTwice: return KeyboardShortcut(key: "fn", pressCount: 2)
        case .controlTwice: return KeyboardShortcut(key: "control", pressCount: 2)
        case .optionTwice: return KeyboardShortcut(key: "option", pressCount: 2)
        case .commandTwice: return KeyboardShortcut(key: "command", pressCount: 2)
        }
    }
}

public struct TargetConfiguration: Codable, Equatable {
    public var kind: DictationTargetKind
    public var submitWithEnter: Bool
    public var submitDelayMilliseconds: Int
    public var nativeShortcut: NativeDictationShortcut
    public var customStartShortcut: String
    public var customStopShortcut: String

    public init(
        kind: DictationTargetKind = .handy,
        submitWithEnter: Bool = true,
        submitDelayMilliseconds: Int = 1_500,
        nativeShortcut: NativeDictationShortcut = .functionTwice,
        customStartShortcut: String = "command+shift+d",
        customStopShortcut: String = "command+shift+d"
    ) {
        self.kind = kind
        self.submitWithEnter = submitWithEnter
        self.submitDelayMilliseconds = min(max(submitDelayMilliseconds, 0), 10_000)
        self.nativeShortcut = nativeShortcut
        self.customStartShortcut = customStartShortcut
        self.customStopShortcut = customStopShortcut
    }

    public static let `default` = TargetConfiguration()
}

public final class TargetConfigurationStore {
    private static let key = "targetConfiguration"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> TargetConfiguration {
        guard let data = defaults.data(forKey: Self.key),
              let configuration = try? JSONDecoder().decode(
                TargetConfiguration.self,
                from: data
              ) else {
            save(.default)
            return .default
        }
        return configuration
    }

    public func save(_ configuration: TargetConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
