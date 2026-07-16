import AppKit
import Darwin
import Foundation
import PD200XTarget

private enum ButtonMode: String {
    case dictation
    case meeting

    var menuTitle: String {
        switch self {
        case .dictation: return "Dictation Mode — use configured target"
        case .meeting: return "Meeting Mode — button mutes microphone"
        }
    }

    var statusTitle: String {
        switch self {
        case .dictation: return "Dictate"
        case .meeting: return "Meeting"
        }
    }
}

private enum LoginAgent {
    static let label = "com.maulik.pd200x-button"

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
            .appendingPathComponent("\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    static func install() throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        guard let executablePath = Bundle.main.executableURL?.path else {
            throw LoginAgentError.missingExecutable
        }
        let propertyList: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
    }

    static func remove() throws {
        try FileManager.default.removeItem(at: url)
    }
}

private enum LoginAgentError: Error, LocalizedError {
    case missingExecutable

    var errorDescription: String? {
        "The menu app executable could not be found."
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let modeKey = "buttonMode"

    private let defaults = UserDefaults.standard
    private let targetStore = TargetConfigurationStore()
    private var mode = ButtonMode.dictation
    private var statusItem: NSStatusItem!
    private var currentModeItem: NSMenuItem!
    private var currentTargetItem: NSMenuItem!
    private var dictationItem: NSMenuItem!
    private var meetingItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    private var settingsWindowController: SettingsWindowController?
    private var helperProcess: Process?
    private var wantsHelper = false
    private var terminationSignalSources: [DispatchSourceSignal] = []
    private var targetIsActive = false
    private var targetError: String?
    private lazy var targetSession: DictationTargetSession = {
        let session = DictationTargetSession(store: targetStore)
        session.onStateChange = { [weak self] active, error in
            self?.targetIsActive = active
            self?.targetError = error
            self?.updateInterface()
        }
        return session
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installTerminationHandlers()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receiveModeChange(_:)),
            name: PD200XNotifications.changeMode,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(receivePhysicalButtonPress),
            name: PD200XNotifications.physicalButtonPressed,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showSettings),
            name: PD200XNotifications.showSettings,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        mode = defaults.string(forKey: Self.modeKey)
            .flatMap(ButtonMode.init(rawValue:))
            ?? .dictation
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        _ = targetSession
        makeStatusItem()
        applySelectedMode()
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        targetSession.cancelAndWait()
        wantsHelper = false
        stopHelper()
    }

    @objc private func receiveModeChange(_ notification: Notification) {
        guard let rawMode = notification.object as? String,
              let requestedMode = ButtonMode(rawValue: rawMode) else { return }
        setMode(requestedMode)
    }

    @objc private func receivePhysicalButtonPress() {
        guard mode == .dictation else { return }
        targetSession.toggle()
    }

    private func makeStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)

        let menu = NSMenu()
        let heading = NSMenuItem(title: "PD200X Button", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        currentModeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        currentModeItem.isEnabled = false
        menu.addItem(currentModeItem)

        currentTargetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        currentTargetItem.isEnabled = false
        menu.addItem(currentTargetItem)
        menu.addItem(.separator())

        dictationItem = NSMenuItem(
            title: ButtonMode.dictation.menuTitle,
            action: #selector(selectDictationMode),
            keyEquivalent: "d"
        )
        dictationItem.target = self
        menu.addItem(dictationItem)

        meetingItem = NSMenuItem(
            title: ButtonMode.meeting.menuTitle,
            action: #selector(selectMeetingMode),
            keyEquivalent: "m"
        )
        meetingItem.target = self
        menu.addItem(meetingItem)

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        launchAtLoginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)

        let quitItem = NSMenuItem(
            title: "Quit and Restore Normal Mute",
            action: #selector(quitAndRestoreNormalMute),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        updateInterface()
    }

    @objc private func selectDictationMode() {
        setMode(.dictation)
    }

    @objc private func selectMeetingMode() {
        setMode(.meeting)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if LoginAgent.isInstalled {
                try LoginAgent.remove()
            } else {
                try LoginAgent.install()
            }
            updateInterface()
        } catch {
            showError("The login setting could not be changed: \(error.localizedDescription)")
        }
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                configuration: targetStore.load(),
                onSave: { [weak self] configuration in
                    guard let self else { return }
                    try self.targetSession.updateConfiguration(configuration)
                    self.targetError = nil
                    self.updateInterface()
                    self.settingsWindowController = nil
                }
            )
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitAndRestoreNormalMute() {
        setMode(.meeting)
        NSApp.terminate(nil)
    }

    private func setMode(_ newMode: ButtonMode) {
        guard newMode != mode else { return }
        mode = newMode
        defaults.set(mode.rawValue, forKey: Self.modeKey)
        applySelectedMode()
    }

    private func applySelectedMode() {
        switch mode {
        case .dictation:
            startHelper()
        case .meeting:
            targetSession.cancelAndWait()
            wantsHelper = false
            stopHelper()
        }
        updateInterface()
    }

    private func startHelper() {
        guard helperProcess?.isRunning != true else {
            wantsHelper = true
            return
        }

        wantsHelper = true
        let process = Process()
        process.executableURL = helperExecutableURL
        process.arguments = [
            "--dictation-service",
            "--parent-pid",
            String(getpid()),
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                guard let self else { return }
                if self.helperProcess === finishedProcess {
                    self.helperProcess = nil
                }
                if self.wantsHelper, self.mode == .dictation {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.startHelper()
                    }
                }
            }
        }

        do {
            try process.run()
            helperProcess = process
        } catch {
            wantsHelper = false
            showError("Dictation mode could not start: \(error.localizedDescription)")
        }
    }

    private func stopHelper() {
        guard let process = helperProcess else { return }
        helperProcess = nil
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }

    private func updateInterface() {
        let configuration = targetStore.load()
        statusItem.button?.title = mode.statusTitle
        statusItem.button?.toolTip = mode.menuTitle
        currentModeItem.title = "Current: \(mode == .dictation ? "Dictation" : "Meeting")"
        if let targetError {
            currentTargetItem.title = "Target error: \(targetError)"
        } else if mode == .meeting {
            currentTargetItem.title = "Target: \(configuration.kind.displayName) — paused"
        } else {
            currentTargetItem.title = "Target: \(configuration.kind.displayName) — \(targetIsActive ? "active" : "ready")"
        }
        dictationItem.state = mode == .dictation ? .on : .off
        meetingItem.state = mode == .meeting ? .on : .off
        launchAtLoginItem.state = LoginAgent.isInstalled ? .on : .off
    }

    private var helperExecutableURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/pd200x-button-helper")
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "PD200X Button"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    private func installTerminationHandlers() {
        for signalNumber in [SIGINT, SIGTERM] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(
                signal: signalNumber,
                queue: .main
            )
            source.setEventHandler {
                NSApp.terminate(nil)
            }
            source.resume()
            terminationSignalSources.append(source)
        }
    }
}

if CommandLine.arguments.contains("--install-login-agent") {
    do {
        try LoginAgent.install()
    } catch {
        FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
        exit(EXIT_FAILURE)
    }
} else if let argumentIndex = CommandLine.arguments.firstIndex(of: "--set-mode"),
   CommandLine.arguments.indices.contains(argumentIndex + 1),
   let requestedMode = ButtonMode(rawValue: CommandLine.arguments[argumentIndex + 1]) {
    DistributedNotificationCenter.default().postNotificationName(
        PD200XNotifications.changeMode,
        object: requestedMode.rawValue,
        userInfo: nil,
        deliverImmediately: true
    )
} else if CommandLine.arguments.contains("--show-settings") {
    DistributedNotificationCenter.default().postNotificationName(
        PD200XNotifications.showSettings,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
} else if CommandLine.arguments.contains("--simulate-button-press") {
    DistributedNotificationCenter.default().postNotificationName(
        PD200XNotifications.physicalButtonPressed,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
