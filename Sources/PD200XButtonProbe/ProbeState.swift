import Foundation

struct ReportDifference: Equatable {
    let byteOffset: Int
    let before: UInt8
    let after: UInt8
    let beforeConfidence: Double
    let afterConfidence: Double
}

struct ProbeState {
    var deviceName = "PD200X Podcast Microphone"
    var isConnected = false
    var rollingVendorSamples = 0
    var baselineSamples = 0
    var consumerEvents: [String] = []
    var differences: [ReportDifference] = []
    var status = "Collecting the current state."
    var queryPreview = "not previewed"
    var readRequestsSent = 0
    var observedMuteState = "not queried"
    var lastMuteReply = "none"
    var rawReportsObserved = 0
    var lastRawReport = "none"
    var error: String?
}

enum ProbeAction {
    case connected
    case disconnected
    case sampleCountChanged(Int)
    case baselineCaptured(Int)
    case consumerEvent(String)
    case comparisonCompleted([ReportDifference], sampleCount: Int)
    case queryPreviewed(String)
    case readRequestSent
    case muteStateObserved(Bool, reply: String)
    case rawReportObserved(String)
    case reset
    case failed(String)
}

func reduce(_ state: ProbeState, _ action: ProbeAction) -> ProbeState {
    var next = state

    switch action {
    case .connected:
        next.isConnected = true
        next.error = nil

    case .disconnected:
        next.isConnected = false
        next.status = "The microphone is disconnected."

    case let .sampleCountChanged(count):
        next.rollingVendorSamples = count

    case let .baselineCaptured(count):
        next.baselineSamples = count
        next.rollingVendorSamples = 0
        next.differences = []
        next.status = "Baseline captured. Press mute once, wait, then compare."

    case let .consumerEvent(event):
        next.consumerEvents.append(event)
        next.consumerEvents = Array(next.consumerEvents.suffix(6))

    case let .comparisonCompleted(differences, sampleCount):
        next.differences = differences
        next.rollingVendorSamples = sampleCount
        next.status = differences.isEmpty
            ? "No stable vendor-report difference found."
            : "Found stable vendor-report differences."

    case let .queryPreviewed(packet):
        next.queryPreview = packet
        next.status = "The permitted read-only packet is ready for inspection."

    case .readRequestSent:
        next.readRequestsSent += 1
        next.status = "One mute-state read request was sent. Waiting for its reply."

    case let .muteStateObserved(isMuted, reply):
        next.observedMuteState = isMuted ? "muted" : "unmuted"
        next.lastMuteReply = reply
        next.status = "The microphone replied with its current mute state."

    case let .rawReportObserved(report):
        next.rawReportsObserved += 1
        next.lastRawReport = report
        next.status = "A raw input report was observed."

    case .reset:
        let sent = state.readRequestsSent
        let rawCount = state.rawReportsObserved
        next = ProbeState()
        next.isConnected = state.isConnected
        next.readRequestsSent = sent
        next.rawReportsObserved = rawCount
        next.status = "Observations cleared. Collecting a new current state."

    case let .failed(message):
        next.error = message
        next.status = "Probe failed."
    }

    return next
}
