import Foundation

func timeString(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded())
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let rest = total % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, rest)
    }
    return String(format: "%d:%02d", minutes, rest)
}

func durationString(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, seconds > 0 else { return "--:--" }
    return timeString(seconds)
}
