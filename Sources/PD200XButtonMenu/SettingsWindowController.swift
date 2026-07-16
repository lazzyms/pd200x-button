import AppKit
import PD200XTarget
import SwiftUI

final class SettingsWindowController: NSWindowController {
    init(
        configuration: TargetConfiguration,
        onSave: @escaping (TargetConfiguration) throws -> Void
    ) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 570),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PD200X Button Settings"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        let view = TargetSettingsView(
            configuration: configuration,
            onSave: { [weak self] updated in
                try onSave(updated)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        window.contentViewController = NSHostingController(rootView: view)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TargetSettingsModel: ObservableObject {
    @Published var kind: DictationTargetKind
    @Published var submitWithEnter: Bool
    @Published var submitDelaySeconds: Double
    @Published var nativeShortcut: NativeDictationShortcut
    @Published var customStartShortcut: String
    @Published var customStopShortcut: String
    @Published var keyboardAccess = KeyboardEventPoster.hasPermission
    @Published var errorMessage: String?

    init(configuration: TargetConfiguration) {
        kind = configuration.kind
        submitWithEnter = configuration.submitWithEnter
        submitDelaySeconds = Double(configuration.submitDelayMilliseconds) / 1_000
        nativeShortcut = configuration.nativeShortcut
        customStartShortcut = configuration.customStartShortcut
        customStopShortcut = configuration.customStopShortcut
    }

    func configuration() throws -> TargetConfiguration {
        if kind == .customShortcut {
            _ = try KeyboardShortcut.parse(customStartShortcut)
            _ = try KeyboardShortcut.parse(customStopShortcut)
        }
        return TargetConfiguration(
            kind: kind,
            submitWithEnter: submitWithEnter,
            submitDelayMilliseconds: Int((submitDelaySeconds * 1_000).rounded()),
            nativeShortcut: nativeShortcut,
            customStartShortcut: customStartShortcut,
            customStopShortcut: customStopShortcut
        )
    }

    func requestKeyboardAccess() {
        _ = KeyboardEventPoster.requestPermission()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.keyboardAccess = KeyboardEventPoster.hasPermission
        }
    }

    func openDictationSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct TargetSettingsView: View {
    @StateObject private var model: TargetSettingsModel
    let onSave: (TargetConfiguration) throws -> Void
    let onCancel: () -> Void

    init(
        configuration: TargetConfiguration,
        onSave: @escaping (TargetConfiguration) throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: TargetSettingsModel(configuration: configuration))
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PD200X Button")
                    .font(.title2.weight(.semibold))
                Text("Choose what one press starts and the next press stops.")
                    .foregroundStyle(.secondary)
            }

            GroupBox("Dictation target") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Target", selection: $model.kind) {
                        ForEach(DictationTargetKind.allCases, id: \.self) {
                            Text($0.displayName).tag($0)
                        }
                    }

                    if model.kind == .macOSDictation {
                        Picker("Dictation shortcut", selection: $model.nativeShortcut) {
                            ForEach(NativeDictationShortcut.allCases, id: \.self) {
                                Text($0.displayName).tag($0)
                            }
                        }
                        Text("Choose the same shortcut in macOS Keyboard settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Open macOS Dictation Settings") {
                            model.openDictationSettings()
                        }
                    }

                    if model.kind == .customShortcut {
                        TextField("Start shortcut", text: $model.customStartShortcut)
                        TextField("Stop shortcut", text: $model.customStopShortcut)
                        Text("Examples: command+shift+d, option+space, or control control.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }

            GroupBox("After stopping") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Press Enter to submit", isOn: $model.submitWithEnter)
                    HStack {
                        Text("Wait before Enter")
                        Slider(value: $model.submitDelaySeconds, in: 0...10, step: 0.1)
                            .disabled(!model.submitWithEnter)
                        Text(String(format: "%.1f s", model.submitDelaySeconds))
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
                .padding(6)
            }

            GroupBox("Keyboard Control permission") {
                HStack {
                    Image(systemName: model.keyboardAccess
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.keyboardAccess ? .green : .orange)
                    Text(model.keyboardAccess
                        ? "Ready to send shortcuts and Enter."
                        : "Required for macOS Dictation, custom shortcuts, and Enter submission.")
                    Spacer()
                    if !model.keyboardAccess {
                        Button("Request Access") {
                            model.requestKeyboardAccess()
                        }
                    }
                }
                .padding(6)
            }

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    do {
                        try onSave(model.configuration())
                    } catch {
                        model.errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 570, height: 570)
    }
}
