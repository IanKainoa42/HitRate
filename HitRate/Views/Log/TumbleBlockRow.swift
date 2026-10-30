import SwiftUI

/// The coach can inspect each building block before exporting its full pose table.
struct TumbleBlockRow: View {
    let block: TumbleArchive.Block
    let athlete: String

    private var measurements: String {
        var parts: [String] = []
        if let stroke = block.inOutStroke {
            parts.append(String(format: "In %.1f°", stroke.inDegrees))
            parts.append(String(format: "Out %.1f°", stroke.outDegrees))
        }
        if let launch = block.launchDegrees {
            parts.append(String(format: "Launch %.1f°", launch))
        }
        if let flip = block.takeoffSpeeds.first?.flip ?? block.takeoffRatings.first?.flipRPS {
            parts.append(String(format: "Flip %.2f rps", flip))
        }
        if let twist = block.takeoffSpeeds.first?.twist ?? block.takeoffRatings.first?.twistRPS {
            parts.append(String(format: "Twist %.2f rps", twist))
        }
        return parts.isEmpty ? "No measured takeoff yet" : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(athlete) · \(block.skill)")
                .font(.subheadline.weight(.semibold))
            Text(measurements)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
