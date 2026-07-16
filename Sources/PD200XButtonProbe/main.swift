import Foundation
import IOKit
import IOKit.hid
import Darwin
import PD200XTarget

private let vendorID = 13_615
private let productID = 260
private let vendorReportID: CFIndex = 75
private let comparisonReportLimit = 300
private let isDictationService = CommandLine.arguments.contains("--dictation-service")
private let serviceParentPID: pid_t? = {
    guard let index = CommandLine.arguments.firstIndex(of: "--parent-pid"),
          CommandLine.arguments.indices.contains(index + 1),
          let value = Int32(CommandLine.arguments[index + 1]),
          value > 1 else { return nil }
    return value
}()
private enum ProbeError: Error, CustomStringConvertible {
    case hidManager(IOReturn)

    var description: String {
        switch self {
        case let .hidManager(status):
            return "The Human Interface Device manager returned status \(status)."
        }
    }
}

private final class ProbeController {
    private let shouldRender: Bool
    private let lock = NSLock()
    private let pollQueue = DispatchQueue(
        label: "com.maulik.pd200x-button.hardware",
        qos: .userInitiated
    )
    private let inputReportBuffer: UnsafeMutablePointer<UInt8>
    private var device: IOHIDDevice?
    private var state = ProbeState()
    private var remapState = ButtonRemapState()
    private var pollTimer: DispatchSourceTimer?
    private var rollingReports: [[UInt8]] = []
    private var baseline: ReportSummary?

    init(shouldRender: Bool = true) {
        self.shouldRender = shouldRender
        inputReportBuffer = .allocate(capacity: MuteQueryProtocol.reportLength)
        inputReportBuffer.initialize(
            repeating: 0,
            count: MuteQueryProtocol.reportLength
        )
    }

    deinit {
        inputReportBuffer.deallocate()
    }

    func dispatch(_ action: ProbeAction, render: Bool = true) {
        lock.lock()
        state = reduce(state, action)
        if render { renderLocked() }
        lock.unlock()
    }

    func attach(_ device: IOHIDDevice) {
        IOHIDDeviceRegisterInputReportCallback(
            device,
            inputReportBuffer,
            MuteQueryProtocol.reportLength,
            inputReportCallback,
            Unmanaged.passUnretained(self).toOpaque()
        )

        lock.lock()
        self.device = device
        state = reduce(state, .connected)
        renderLocked()
        lock.unlock()
    }

    func detach(_ removedDevice: IOHIDDevice) {
        lock.lock()
        if device === removedDevice {
            device = nil
            state = reduce(state, .disconnected)
            renderLocked()
        }
        lock.unlock()
    }

    func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let reportID = IOHIDElementGetReportID(element)

        if page == 12 {
            let integerValue = IOHIDValueGetIntegerValue(value)
            dispatch(.consumerEvent("usage \(usage), value \(integerValue)"))
            return
        }

        guard reportID == vendorReportID else { return }
        let length = IOHIDValueGetLength(value)
        let pointer = IOHIDValueGetBytePtr(value)
        let report = Array(UnsafeBufferPointer(start: pointer, count: length))

        if let isMuted = MuteQueryProtocol.parseReadResponse(payload: report) {
            lock.lock()
            let remapIsEnabled = remapState.isEnabled
            lock.unlock()
            if !remapIsEnabled {
                dispatch(.muteStateObserved(isMuted, reply: MuteQueryProtocol.hex(report)))
            }
            return
        }

        lock.lock()
        let remapIsEnabled = remapState.isEnabled
        lock.unlock()
        if remapIsEnabled { return }

        lock.lock()
        rollingReports.append(report)
        if rollingReports.count > comparisonReportLimit {
            rollingReports.removeFirst(rollingReports.count - comparisonReportLimit)
        }
        state = reduce(state, .sampleCountChanged(rollingReports.count))
        lock.unlock()
    }

    func receiveRawReport(
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>,
        length: CFIndex
    ) {
        guard length > 0 else { return }
        let bytes = Array(UnsafeBufferPointer(start: report, count: length))
        let description = "identifier \(reportID): \(MuteQueryProtocol.hex(bytes))"

        let observedMute = MuteQueryProtocol.parseRawReadResponse(report: bytes)
            ?? MuteQueryProtocol.parseReadResponse(payload: bytes)
        guard let observedMute else { return }

        lock.lock()
        let remapIsEnabled = remapState.isEnabled
        lock.unlock()

        if remapIsEnabled {
            handleRemapMuteObservation(observedMute, reply: description)
            return
        }

        dispatch(.rawReportObserved(description))
        dispatch(.muteStateObserved(observedMute, reply: description))
    }

    func previewMuteQuery() {
        let packet = MuteQueryProtocol.makeReadPacket()
        dispatch(.queryPreviewed(MuteQueryProtocol.hex(packet)))
    }

    func sendMuteQuery(render: Bool = true) {
        lock.lock()
        guard let device else {
            if render {
                state = reduce(state, .failed("The PD200X Human Interface Device is not connected."))
                renderLocked()
            }
            lock.unlock()
            return
        }

        let packet = MuteQueryProtocol.makeReadPacket()
        guard MuteQueryProtocol.isPermittedRead(packet) else {
            state = reduce(state, .failed("The local safety guard rejected the query packet."))
            if render { renderLocked() }
            lock.unlock()
            return
        }
        lock.unlock()

        let status = packet.withUnsafeBytes { bytes -> IOReturn in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                vendorReportID,
                pointer,
                packet.count
            )
        }

        if status == kIOReturnSuccess {
            dispatch(.readRequestSent, render: render)
        } else if render {
            dispatch(.failed("The read request was not sent. Human Interface Device status: \(status)."))
        }
    }

    func startDictationRemap() {
        lock.lock()
        guard pollTimer == nil else {
            renderLocked()
            lock.unlock()
            return
        }

        remapState = transition(remapState, .start).state
        let timer = DispatchSource.makeTimerSource(queue: pollQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(80))
        timer.setEventHandler { [weak self] in
            self?.sendMuteQuery(render: false)
        }
        pollTimer = timer
        renderLocked()
        lock.unlock()
        timer.resume()
    }

    func stopDictationRemap() {
        lock.lock()
        guard pollTimer != nil || remapState.isEnabled else {
            renderLocked()
            lock.unlock()
            return
        }
        let timer = pollTimer
        pollTimer = nil
        remapState = transition(remapState, .stop).state
        renderLocked()
        lock.unlock()

        timer?.cancel()
    }

    func shutdown() {
        stopDictationRemap()
    }

    private func handleRemapMuteObservation(_ isMuted: Bool, reply: String) {
        lock.lock()
        let previous = remapState
        let result = transition(remapState, .observedMute(isMuted))
        remapState = result.state
        state.observedMuteState = isMuted ? "muted" : "unmuted"
        state.lastMuteReply = reply
        let shouldRender = previous != remapState || !result.effects.isEmpty
        if shouldRender { renderLocked() }
        lock.unlock()

        for effect in result.effects {
            switch effect {
            case .forceUnmute:
                forceUnmute()
            case .buttonPressed:
                handleConfiguredButtonPress()
            }
        }
    }

    private func forceUnmute() {
        lock.lock()
        guard let device else {
            lock.unlock()
            return
        }
        let packet = MuteQueryProtocol.makeForceUnmutePacket()
        guard MuteQueryProtocol.isPermittedForceUnmute(packet) else {
            remapState = transition(
                remapState,
                .targetToggleFailed("the force-unmute safety guard rejected its packet")
            ).state
            renderLocked()
            lock.unlock()
            return
        }
        lock.unlock()

        let status = packet.withUnsafeBytes { bytes -> IOReturn in
            let pointer = bytes.bindMemory(to: UInt8.self).baseAddress!
            return IOHIDDeviceSetReport(
                device,
                kIOHIDReportTypeOutput,
                vendorReportID,
                pointer,
                packet.count
            )
        }

        guard status != kIOReturnSuccess else { return }
        lock.lock()
        remapState = transition(
            remapState,
            .targetToggleFailed("the microphone could not be restored to unmuted; status \(status)")
        ).state
        renderLocked()
        lock.unlock()
    }

    private func handleConfiguredButtonPress() {
        DistributedNotificationCenter.default().postNotificationName(
            PD200XNotifications.physicalButtonPressed,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
        completeTargetToggle(error: nil)
    }

    private func completeTargetToggle(error: String?) {
        lock.lock()
        remapState = transition(
            remapState,
            error.map(ButtonRemapEvent.targetToggleFailed)
                ?? .targetToggleCompleted
        ).state
        renderLocked()
        lock.unlock()
    }

    func captureBaseline() {
        lock.lock()
        guard let summary = summarize(rollingReports) else {
            state = reduce(state, .failed("No vendor reports were available for the baseline."))
            renderLocked()
            lock.unlock()
            return
        }
        baseline = summary
        rollingReports.removeAll(keepingCapacity: true)
        state = reduce(state, .baselineCaptured(summary.sampleCount))
        renderLocked()
        lock.unlock()
    }

    func compare() {
        lock.lock()
        guard let baseline else {
            state = reduce(state, .failed("Capture a baseline before comparing."))
            renderLocked()
            lock.unlock()
            return
        }
        guard let current = summarize(rollingReports) else {
            state = reduce(state, .failed("No vendor reports were available to compare."))
            renderLocked()
            lock.unlock()
            return
        }
        let differences = stableDifferences(between: baseline, and: current)
        state = reduce(
            state,
            .comparisonCompleted(differences, sampleCount: current.sampleCount)
        )
        renderLocked()
        lock.unlock()
    }

    func reset() {
        lock.lock()
        baseline = nil
        rollingReports.removeAll(keepingCapacity: true)
        state = reduce(state, .reset)
        renderLocked()
        lock.unlock()
    }

    private func renderLocked() {
        guard shouldRender else { return }
        let bold = "\u{001B}[1m"
        let dim = "\u{001B}[2m"
        let reset = "\u{001B}[0m"
        let clear = "\u{001B}[2J\u{001B}[H"

        var lines = [
            "\(clear)\(bold)PD200X BUTTON — guarded hardware probe\(reset)",
            "\(dim)Manual dictation remap for protocol inspection and testing.\(reset)",
            "",
            "\(bold)Safety mode:\(reset) allow-listed state query and force-unmute only; persistence: none",
            "\(bold)Device:\(reset) \(state.deviceName)",
            "\(bold)Connected:\(reset) \(state.isConnected ? "yes" : "no")",
            "\(bold)Dictation remap enabled:\(reset) \(remapState.isEnabled ? "yes" : "no")",
            "\(bold)Button armed:\(reset) \(remapState.isArmed ? "yes" : "no")",
            "\(bold)Target active expected:\(reset) \(remapState.targetActiveExpected ? "yes" : "no")",
            "\(bold)Successful button presses:\(reset) \(remapState.successfulButtonPresses)",
            "\(bold)Remapper status:\(reset) \(remapState.status)",
            "\(bold)Rolling vendor samples:\(reset) \(state.rollingVendorSamples)",
            "\(bold)Baseline samples:\(reset) \(state.baselineSamples)",
            "\(bold)Status:\(reset) \(state.status)",
            "\(bold)Read requests sent:\(reset) \(state.readRequestsSent)",
            "\(bold)Observed hardware mute:\(reset) \(state.observedMuteState)",
            "\(bold)Last matching reply:\(reset) \(state.lastMuteReply)",
            "\(bold)Raw reports observed:\(reset) \(state.rawReportsObserved)",
            "\(bold)Last raw report:\(reset) \(state.lastRawReport)",
            "\(bold)Permitted packet preview:\(reset) \(state.queryPreview)",
            "",
            "\(bold)Stable changed bytes:\(reset)",
        ]

        if state.differences.isEmpty {
            lines.append("none")
        } else {
            for difference in state.differences.prefix(12) {
                let before = String(format: "%02X", difference.before)
                let after = String(format: "%02X", difference.after)
                lines.append("byte \(difference.byteOffset): \(before) to \(after)")
            }
        }

        lines.append("")
        lines.append("\(bold)Standard consumer-control events:\(reset)")
        lines.append(contentsOf: state.consumerEvents.isEmpty ? ["none"] : state.consumerEvents)

        if let error = state.error {
            lines.append("\n\(bold)Error:\(reset) \(error)")
        }

        lines.append(contentsOf: [
            "",
            "Enter \(bold)d\(reset) to enable the dictation remap or \(bold)x\(reset) to restore normal mute.",
            "Enter \(bold)p\(reset) to preview the sole permitted query. Enter \(bold)m\(reset) to send it once.",
            "Enter \(bold)b\(reset) to capture baseline. Enter \(bold)a\(reset) to compare after pressing mute.",
            "Enter \(bold)r\(reset) to clear observations. Enter \(bold)q\(reset) to quit.",
            "\(dim)Quitting disables polling and returns the button to its original mute behavior.\(reset)",
        ])

        print(lines.joined(separator: "\n"))
        fflush(stdout)
    }
}

private func inputReportCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    type: IOHIDReportType,
    reportID: UInt32,
    report: UnsafeMutablePointer<UInt8>,
    reportLength: CFIndex
) {
    guard let context, result == kIOReturnSuccess else { return }
    let controller = Unmanaged<ProbeController>.fromOpaque(context).takeUnretainedValue()
    controller.receiveRawReport(reportID: reportID, report: report, length: reportLength)
}

private func deviceMatchingCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let controller = Unmanaged<ProbeController>.fromOpaque(context).takeUnretainedValue()
    controller.attach(device)
}

private func deviceRemovalCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let context else { return }
    let controller = Unmanaged<ProbeController>.fromOpaque(context).takeUnretainedValue()
    controller.detach(device)
}

private func inputValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let context else { return }
    let controller = Unmanaged<ProbeController>.fromOpaque(context).takeUnretainedValue()
    controller.receive(value)
}

private let controller = ProbeController(shouldRender: !isDictationService)
private let manager = IOHIDManagerCreate(
    kCFAllocatorDefault,
    IOOptionBits(kIOHIDOptionsTypeNone)
)
private let context = Unmanaged.passUnretained(controller).toOpaque()
private let runLoop = CFRunLoopGetCurrent()!

let matching: [String: Any] = [
    kIOHIDVendorIDKey as String: vendorID,
    kIOHIDProductIDKey as String: productID,
]
IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
IOHIDManagerRegisterDeviceMatchingCallback(manager, deviceMatchingCallback, context)
IOHIDManagerRegisterDeviceRemovalCallback(manager, deviceRemovalCallback, context)
IOHIDManagerRegisterInputValueCallback(manager, inputValueCallback, context)
IOHIDManagerScheduleWithRunLoop(
    manager,
    runLoop,
    CFRunLoopMode.defaultMode.rawValue
)

let openStatus = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
guard openStatus == kIOReturnSuccess else {
    controller.dispatch(.failed(String(describing: ProbeError.hidManager(openStatus))))
    exit(1)
}
controller.dispatch(.reset)

private var signalSources: [DispatchSourceSignal] = []
private var parentMonitor: DispatchSourceTimer?

private func installTerminationHandlers() {
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(
            signal: signalNumber,
            queue: .main
        )
        source.setEventHandler {
            controller.shutdown()
            CFRunLoopStop(runLoop)
        }
        source.resume()
        signalSources.append(source)
    }
}

private func installParentMonitor() {
    guard let serviceParentPID else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: .seconds(1))
    timer.setEventHandler {
        if kill(serviceParentPID, 0) == -1, errno == ESRCH {
            controller.shutdown()
            CFRunLoopStop(runLoop)
        }
    }
    timer.resume()
    parentMonitor = timer
}

if isDictationService {
    installTerminationHandlers()
    installParentMonitor()
    controller.startDictationRemap()
} else {
    DispatchQueue.global(qos: .userInitiated).async {
        while let command = readLine()?.lowercased() {
            switch command {
            case "d": controller.startDictationRemap()
            case "x": controller.stopDictationRemap()
            case "p": controller.previewMuteQuery()
            case "m": controller.sendMuteQuery()
            case "b": controller.captureBaseline()
            case "a": controller.compare()
            case "r": controller.reset()
            case "q":
                controller.shutdown()
                CFRunLoopStop(runLoop)
                return
            default: break
            }
        }
        controller.shutdown()
        CFRunLoopStop(runLoop)
    }
}

CFRunLoopRun()
IOHIDManagerUnscheduleFromRunLoop(
    manager,
    runLoop,
    CFRunLoopMode.defaultMode.rawValue
)
IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
