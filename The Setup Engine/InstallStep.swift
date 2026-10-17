import SwiftUI

struct InstallStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator

    var body: some View {
        VStack(spacing: 0) {
            if coordinator.installComplete {
                completeView
            } else {
                inProgressView
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - In progress

    private var inProgressView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 24)

            currentTile

            progressBar

            Spacer()

            Text("Sit back — we'll let you know when it's done.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    private var currentTile: some View {
        let total = coordinator.selectedApps.count
        let idx   = min(coordinator.currentInstallIndex, max(0, total - 1))
        let current = total > 0 ? coordinator.selectedApps[idx] : nil
        let status = current.flatMap { coordinator.itemStatuses[$0.caskName] }
        let isSkipped = status == .skipped

        return VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(.regularMaterial)
                    .frame(width: 140, height: 140)

                if let current {
                    CaskIconView(homepageURL: current.homepageURL, caskName: current.caskName)
                        .frame(width: 96, height: 96)
                } else {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.tint)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isSkipped {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 8, y: 8)
                } else if status == .waitingForPassword {
                    Image(systemName: "lock.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .padding(6)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 8, y: 8)
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 8, y: 8)
                }
            }

            VStack(spacing: 4) {
                Text(headline(for: current, status: status))
                    .font(.system(size: 22, weight: .semibold))
                    .multilineTextAlignment(.center)

                Text(subline(total: total, index: idx, status: status))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private func headline(for app: AppEntry?, status: SetupCoordinator.ItemStatus?) -> String {
        guard let app else { return "Applying your settings…" }
        switch status {
        case .skipped:            return "\(app.displayName) — already installed"
        case .downloading:        return "Downloading \(app.displayName)…"
        case .verifying:          return "Checking \(app.displayName) with Apple…"
        case .waitingForPassword: return "Enter your Mac's password to finish"
        case .failed:             return "\(app.displayName) didn't install"
        default:                  return "Installing \(app.displayName)…"
        }
    }

    private func subline(total: Int, index: Int, status: SetupCoordinator.ItemStatus?) -> String {
        guard total > 0 else { return "Applying your settings" }
        switch status {
        case .downloading(let p):
            return "App \(index + 1) of \(total) · \(Int(p * 100))%"
        case .waitingForPassword:
            let waiting = coordinator.selectedApps
                .filter { coordinator.itemStatuses[$0.caskName] == .waitingForPassword }
                .map(\.displayName)
            return "Needed for " + ListFormatter.localizedString(byJoining: waiting)
        default:
            return "App \(index + 1) of \(total)"
        }
    }

    private var progressBar: some View {
        let total = max(1, coordinator.selectedApps.count)
        let done = coordinator.selectedApps.filter {
            coordinator.itemStatuses[$0.caskName]?.isFinished == true
        }.count
        // Count the current download's progress so the bar moves during big downloads.
        let partial = coordinator.selectedApps.reduce(0.0) { sum, app in
            if case .downloading(let p) = coordinator.itemStatuses[app.caskName] { return sum + p * 0.8 }
            if coordinator.itemStatuses[app.caskName] == .verifying { return sum + 0.85 }
            return sum
        }
        let value = min(1, (Double(done) + partial) / Double(total))

        return VStack(spacing: 6) {
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(.accentColor)

            HStack {
                Text("\(done) of \(total) apps")
                Spacer()
                Text("\(Int(value * 100))%")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 540)
        .padding(.top, 8)
    }

    // MARK: - Complete

    private var completeView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 24)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80, weight: .light))
                .foregroundStyle(.green)

            Text(coordinator.failedItems.isEmpty
                 ? "Setup complete"
                 : "Mostly done")
                .font(.system(size: 32, weight: .bold))

            if coordinator.failedItems.isEmpty {
                Text("Your apps are installed and your settings are applied.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Some apps couldn't be installed:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    ForEach(coordinator.selectedApps.filter { coordinator.failureReasons[$0.caskName] != nil }) { app in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(app.displayName)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.orange)
                            Text(coordinator.failureReasons[app.caskName] ?? "")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: 540, alignment: .leading)
            }

            Spacer()
        }
    }
}

#Preview {
    InstallStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 880, height: 620)
}
