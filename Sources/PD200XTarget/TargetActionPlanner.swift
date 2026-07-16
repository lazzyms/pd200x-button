import Foundation

public enum TargetAction: Equatable {
    case handyToggle
    case handyCancel
    case shortcut(KeyboardShortcut)
    case wait(milliseconds: Int)
    case pressEnter
    case pressEscape
}

public struct TargetActionPlanner {
    public init() {}

    public func toggleActions(
        configuration: TargetConfiguration,
        isStopping: Bool
    ) throws -> [TargetAction] {
        var actions: [TargetAction]

        switch configuration.kind {
        case .handy:
            actions = [.handyToggle]
        case .macOSDictation:
            actions = [.shortcut(configuration.nativeShortcut.shortcut)]
        case .customShortcut:
            let rawShortcut = isStopping
                ? configuration.customStopShortcut
                : configuration.customStartShortcut
            actions = [.shortcut(try KeyboardShortcut.parse(rawShortcut))]
        }

        if isStopping, configuration.submitWithEnter {
            actions.append(.wait(milliseconds: configuration.submitDelayMilliseconds))
            actions.append(.pressEnter)
        }
        return actions
    }

    public func cancelActions(configuration: TargetConfiguration) -> [TargetAction] {
        switch configuration.kind {
        case .handy: return [.handyCancel]
        case .macOSDictation, .customShortcut: return [.pressEscape]
        }
    }
}
