import Foundation
import PD200XTarget

final class DictationTargetSession {
    private let queue = DispatchQueue(label: "com.maulik.pd200x-button.target")
    private let store: TargetConfigurationStore
    private let planner = TargetActionPlanner()
    private let keyboard = KeyboardEventPoster()
    private let handyExecutable = URL(
        fileURLWithPath: "/Applications/Handy.app/Contents/MacOS/handy"
    )
    private var isActive = false

    var onStateChange: ((Bool, String?) -> Void)?

    init(store: TargetConfigurationStore) {
        self.store = store
    }

    func toggle() {
        queue.async { [weak self] in
            guard let self else { return }
            let configuration = self.store.load()
            let isStopping = self.isActive

            do {
                let actions = try self.planner.toggleActions(
                    configuration: configuration,
                    isStopping: isStopping
                )
                try self.executeToggle(actions, isStopping: isStopping)
                self.report(error: nil)
            } catch {
                self.report(error: error.localizedDescription)
            }
        }
    }

    func updateConfiguration(_ configuration: TargetConfiguration) throws {
        try queue.sync {
            try cancelIfNeeded(configuration: store.load())
            store.save(configuration)
        }
    }

    func cancelAndWait() {
        queue.sync {
            try? cancelIfNeeded(configuration: store.load())
        }
    }

    private func executeToggle(
        _ actions: [TargetAction],
        isStopping: Bool
    ) throws {
        guard let first = actions.first else { return }
        try execute(first)
        isActive = !isStopping
        report(error: nil)

        for action in actions.dropFirst() {
            try execute(action)
        }
    }

    private func cancelIfNeeded(configuration: TargetConfiguration) throws {
        guard isActive else { return }
        defer {
            isActive = false
            report(error: nil)
        }
        for action in planner.cancelActions(configuration: configuration) {
            try execute(action)
        }
    }

    private func execute(_ action: TargetAction) throws {
        switch action {
        case .handyToggle:
            try runHandy("--toggle-transcription")
        case .handyCancel:
            try runHandy("--cancel")
        case let .shortcut(shortcut):
            try keyboard.post(shortcut)
        case let .wait(milliseconds):
            Thread.sleep(forTimeInterval: Double(milliseconds) / 1_000)
        case .pressEnter:
            try keyboard.pressEnter()
        case .pressEscape:
            try keyboard.pressEscape()
        }
    }

    private func runHandy(_ argument: String) throws {
        guard FileManager.default.isExecutableFile(atPath: handyExecutable.path) else {
            throw SessionError.handyNotInstalled
        }
        let process = Process()
        process.executableURL = handyExecutable
        process.arguments = [argument]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SessionError.handyFailed(process.terminationStatus)
        }
    }

    private func report(error: String?) {
        let active = isActive
        DispatchQueue.main.async { [weak self] in
            self?.onStateChange?(active, error)
        }
    }
}

private enum SessionError: Error, LocalizedError {
    case handyNotInstalled
    case handyFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .handyNotInstalled:
            return "Handy is not installed in the Applications folder."
        case let .handyFailed(status):
            return "Handy exited with status \(status)."
        }
    }
}
