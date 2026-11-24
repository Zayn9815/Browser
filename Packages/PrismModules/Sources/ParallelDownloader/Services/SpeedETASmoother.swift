import Foundation

public struct SpeedETASnapshot: Sendable, Equatable {
    public let smoothedBytesPerSecond: UInt64
    public let etaSeconds: Double?
    public let formattedETA: String

    public init(smoothedBytesPerSecond: UInt64, etaSeconds: Double?, formattedETA: String) {
        self.smoothedBytesPerSecond = smoothedBytesPerSecond
        self.etaSeconds = etaSeconds
        self.formattedETA = formattedETA
    }
}

/// Per-transfer Exponential Moving Average (EMA) speed & remaining-time estimator.
/// Keeps displayed ETA steady instead of oscillating on instantaneous network spikes.
public struct SpeedETASmoother: Sendable {
    private let alpha: Double
    private var emaSpeedByTask: [UUID: Double] = [:]
    private var sampleCountByTask: [UUID: Int] = [:]

    public init(alpha: Double = 0.28) {
        self.alpha = min(max(alpha, 0.05), 0.9)
    }

    public mutating func update(
        taskID: UUID,
        instantaneousBytesPerSecond: UInt64,
        downloadedBytes: UInt64,
        totalBytes: UInt64?,
        isActive: Bool
    ) -> SpeedETASnapshot {
        guard isActive else {
            emaSpeedByTask.removeValue(forKey: taskID)
            sampleCountByTask.removeValue(forKey: taskID)
            return SpeedETASnapshot(smoothedBytesPerSecond: 0, etaSeconds: nil, formattedETA: "")
        }

        let rawSpeed = Double(instantaneousBytesPerSecond)
        let samples = (sampleCountByTask[taskID] ?? 0) + 1
        sampleCountByTask[taskID] = samples

        let smoothed: Double
        if let previous = emaSpeedByTask[taskID] {
            smoothed = alpha * rawSpeed + (1.0 - alpha) * previous
        } else {
            smoothed = rawSpeed
        }
        emaSpeedByTask[taskID] = smoothed

        let roundedSpeed = UInt64(max(0, smoothed.rounded()))
        guard let totalBytes, totalBytes > 0 else {
            return SpeedETASnapshot(
                smoothedBytesPerSecond: roundedSpeed,
                etaSeconds: nil,
                formattedETA: "Calculating..."
            )
        }

        if downloadedBytes >= totalBytes {
            return SpeedETASnapshot(
                smoothedBytesPerSecond: roundedSpeed,
                etaSeconds: 0,
                formattedETA: "Finalizing..."
            )
        }

        guard smoothed >= 1024.0, samples >= 2 || rawSpeed >= 16_384.0 else {
            return SpeedETASnapshot(
                smoothedBytesPerSecond: roundedSpeed,
                etaSeconds: nil,
                formattedETA: "Calculating..."
            )
        }

        let remaining = Double(totalBytes - downloadedBytes)
        let eta = min(remaining / smoothed, 86_400 * 7)
        return SpeedETASnapshot(
            smoothedBytesPerSecond: roundedSpeed,
            etaSeconds: eta,
            formattedETA: Self.formatETA(eta)
        )
    }

    public mutating func reset(taskID: UUID) {
        emaSpeedByTask.removeValue(forKey: taskID)
        sampleCountByTask.removeValue(forKey: taskID)
    }

    public static func formatETA(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "Calculating..." }
        let total = Int(seconds.rounded())
        if total <= 1 { return "~1s left" }
        if total < 60 { return "~\(total)s left" }
        let minutes = total / 60
        let secs = total % 60
        if minutes < 60 {
            return String(format: "~%dm %02ds left", minutes, secs)
        }
        let hours = minutes / 60
        let remMin = minutes % 60
        return String(format: "~%dh %02dm left", hours, remMin)
    }
}
