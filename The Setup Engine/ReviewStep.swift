import SwiftUI

struct ReviewStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: 24) {
            StepHero(
                symbol: "checklist",
                title: "Ready to go",
                subtitle: "Here's what The Setup Engine is about to do. You can press Back to change anything."
            )
            .padding(.top, 28)

            HStack(alignment: .top, spacing: 18) {
                appsSummary
                settingsSummary
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: 880)

            pricingHeadsUp

            estimateLine

            Spacer(minLength: 0)
        }
    }

    /// "Heads up" callout listing every selected app with paid features so users
    /// aren't surprised by paywalls after install.
    @ViewBuilder
    private var pricingHeadsUp: some View {
        let paid = coordinator.selectedApps.filter { $0.pricing == .subscription }
        let freemium = coordinator.selectedApps.filter { $0.pricing == .freemium }

        if !paid.isEmpty || !freemium.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.tint)
                    Text("Heads up — paid features")
                        .font(.callout.weight(.semibold))
                }
                if !paid.isEmpty {
                    HStack(spacing: 4) {
                        Text("Subscription required:")
                            .foregroundStyle(.orange)
                        Text(paid.map(\.displayName).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                if !freemium.isEmpty {
                    HStack(spacing: 4) {
                        Text("Freemium (free tier + paid plans):")
                            .foregroundStyle(.blue)
                        Text(freemium.map(\.displayName).joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding(12)
            .frame(maxWidth: 880, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Apps

    private var appsSummary: some View {
        let toInstall = coordinator.appsToInstall
        let alreadyInstalled = coordinator.appsAlreadyInstalled

        return SummaryCard(
            symbol: "app.badge.checkmark",
            title: appsSummaryTitle,
            tint: .indigo
        ) {
            if coordinator.selectedApps.isEmpty {
                Text("No apps selected.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    if !toInstall.isEmpty {
                        chipRow(label: "Will install", apps: toInstall, tint: .indigo)
                    }
                    if !alreadyInstalled.isEmpty {
                        chipRow(
                            label: "Already on your Mac — will skip",
                            apps: alreadyInstalled,
                            tint: .green
                        )
                    }
                }
            }
        }
    }

    private var appsSummaryTitle: String {
        let install = coordinator.appsToInstall.count
        let skip = coordinator.appsAlreadyInstalled.count
        if skip == 0 {
            return "\(install) \(install == 1 ? "app" : "apps")"
        }
        return "\(install) to install · \(skip) skipped"
    }

    private func chipRow(label: String, apps: [AppEntry], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            FlowLayout(spacing: 6) {
                let preview = apps.prefix(7)
                let remaining = max(0, apps.count - preview.count)
                ForEach(Array(preview)) { app in
                    Text(app.displayName)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
                if remaining > 0 {
                    Text("+\(remaining) more")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSummary: some View {
        SummaryCard(
            symbol: "slider.horizontal.3",
            title: "System",
            tint: .blue
        ) {
            VStack(alignment: .leading, spacing: 6) {
                summaryRow("Appearance", coordinator.settings.appearance.label)
                summaryRow("Dock", coordinator.settings.dockPosition.label
                    + (coordinator.settings.dockAutoHide ? " · auto-hide" : ""))
                summaryRow("Finder", finderSummary)
                summaryRow("Time", coordinator.settings.twentyFourHourTime ? "24-hour" : "12-hour")
            }
        }
    }

    private var finderSummary: String {
        var bits: [String] = []
        if coordinator.settings.showPathBar { bits.append("path bar") }
        if coordinator.settings.showHiddenFiles { bits.append("hidden files") }
        return bits.isEmpty ? "Defaults" : bits.joined(separator: " · ")
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
        }
    }

    private var estimateLine: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
                .foregroundStyle(.secondary)
            Text(estimateText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var estimateText: String {
        let n = coordinator.appsToInstall.count
        if n == 0 {
            return "About a minute."
        }
        let lo = max(1, n / 3)
        let hi = max(2, n)
        return "About \(lo)–\(hi) minute\(hi == 1 ? "" : "s") on a typical connection."
    }
}

private struct SummaryCard<Content: View>: View {
    let symbol: String
    let title: String
    let tint: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
                Text(title)
                    .font(.title3.weight(.semibold))
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Flow layout

/// Wraps children onto multiple lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
            totalWidth = max(totalWidth, x)
        }
        return CGSize(width: totalWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}

#Preview {
    ReviewStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
