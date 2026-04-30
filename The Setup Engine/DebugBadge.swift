#if DEBUG
import SwiftUI

/// Small floating pill that makes it obvious the app is in a Debug build,
/// and lights up red when any runtime override is active.
struct DebugBadge: View {
    @ObservedObject var state: DebugState = .shared

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(hasActiveOverride ? Color.red : Color.orange)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(hasActiveOverride ? .red : .orange)
                .monospaced()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(
                    (hasActiveOverride ? Color.red : Color.orange).opacity(0.4),
                    lineWidth: 1
                )
        )
        .help(hoverText)
    }

    private var hasActiveOverride: Bool {
        state.forceNoBrew || state.forceBrewInstallFails || state.fakeAppFailures > 0
    }

    private var label: String {
        var bits = ["DEBUG"]
        if state.forceNoBrew              { bits.append("NO BREW") }
        if state.forceBrewInstallFails    { bits.append("BREW FAILS") }
        if state.fakeAppFailures > 0      { bits.append("FAIL \(state.fakeAppFailures)") }
        return bits.joined(separator: " · ")
    }

    private var hoverText: String {
        if !hasActiveOverride {
            return "Debug build — no overrides active. Open the Debug menu to enable test modes."
        }
        return "Debug overrides are active. Press ⌘⇧R or use Debug → Reset All Overrides to clear."
    }
}
#endif
