import Foundation

enum ButtonRemapEffect: Equatable {
    case forceUnmute
    case buttonPressed
}

struct ButtonRemapState: Equatable {
    var isEnabled = false
    var isArmed = false
    var targetActiveExpected = false
    var successfulButtonPresses = 0
    var status = "Disabled. The microphone button has its original mute function."
}

enum ButtonRemapEvent {
    case start
    case stop
    case observedMute(Bool)
    case targetToggleCompleted
    case targetToggleFailed(String)
}

func transition(
    _ state: ButtonRemapState,
    _ event: ButtonRemapEvent
) -> (state: ButtonRemapState, effects: [ButtonRemapEffect]) {
    var next = state
    var effects: [ButtonRemapEffect] = []

    switch event {
    case .start:
        next.isEnabled = true
        next.isArmed = false
        next.status = "Starting safely. Waiting to confirm that the microphone is unmuted."

    case .stop:
        next.isEnabled = false
        next.isArmed = false
        next.targetActiveExpected = false
        next.status = "Disabled. The microphone button has its original mute function."

    case let .observedMute(isMuted):
        guard next.isEnabled else { break }

        if isMuted {
            effects.append(.forceUnmute)
            if next.isArmed {
                next.isArmed = false
                next.status = "Microphone press detected. Restoring audio and toggling Handy."
                effects.append(.buttonPressed)
            } else {
                next.status = "Restoring the microphone to unmuted before arming."
            }
        } else {
            next.isArmed = true
            next.status = "Ready. One microphone press will toggle Handy dictation."
        }

    case .targetToggleCompleted:
        next.targetActiveExpected.toggle()
        next.successfulButtonPresses += 1
        next.status = next.targetActiveExpected
            ? "Dictation target started. Press the microphone button again to stop."
            : "Dictation target stopped."

    case let .targetToggleFailed(message):
        next.status = "The configured target could not be toggled: \(message)"
    }

    return (next, effects)
}
