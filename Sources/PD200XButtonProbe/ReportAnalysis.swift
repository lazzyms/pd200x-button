import Foundation

struct ReportSummary {
    let sampleCount: Int
    let modes: [UInt8]
    let confidences: [Double]
}

func summarize(_ reports: [[UInt8]]) -> ReportSummary? {
    guard let width = reports.map(\.count).min(), width > 0 else { return nil }

    var modes: [UInt8] = []
    var confidences: [Double] = []

    for offset in 0..<width {
        var counts: [UInt8: Int] = [:]
        for report in reports {
            counts[report[offset], default: 0] += 1
        }
        let mode = counts.max { $0.value < $1.value }!
        modes.append(mode.key)
        confidences.append(Double(mode.value) / Double(reports.count))
    }

    return ReportSummary(
        sampleCount: reports.count,
        modes: modes,
        confidences: confidences
    )
}

func stableDifferences(
    between before: ReportSummary,
    and after: ReportSummary,
    minimumConfidence: Double = 0.9
) -> [ReportDifference] {
    let width = min(before.modes.count, after.modes.count)

    return (0..<width).compactMap { offset in
        guard before.modes[offset] != after.modes[offset],
              before.confidences[offset] >= minimumConfidence,
              after.confidences[offset] >= minimumConfidence
        else { return nil }

        return ReportDifference(
            byteOffset: offset,
            before: before.modes[offset],
            after: after.modes[offset],
            beforeConfidence: before.confidences[offset],
            afterConfidence: after.confidences[offset]
        )
    }
}
