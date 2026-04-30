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
        let isSkipped = current.map { coordinator.itemStatuses[$0.caskName] == .skipped } ?? false

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
                } else {
                    ProgressView()
                        .controlSize(.regular)
                        .padding(8)
                        .background(.regularMaterial, in: Circle())
                        .offset(x: 8, y: 8)
                }
            }

            VStack(spacing: 4) {
                Text(headline(for: current, isSkipped: isSkipped))
                    .font(.system(size: 22, weight: .semibold))

                Text(total > 0
                     ? "App \(idx + 1) of \(total)"
                     : "Applying your settings")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headline(for app: AppEntry?, isSkipped: Bool) -> String {
        guard let app else { return "Applying your settings…" }
        if isSkipped { return "\(app.displayName) — already installed" }
        return "Installing \(app.displayName)…"
    }

    private var progressBar: some View {
        let total = max(1, coordinator.selectedApps.count)
        let done = coordinator.selectedApps.filter {
            switch coordinator.itemStatuses[$0.caskName] {
            case .succeeded, .failed, .skipped: true
            default: false
            }
        }.count
        let value = Double(done) / Double(total)

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
                VStack(spacing: 6) {
                    Text("Some apps couldn't be installed:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(coordinator.failedItems.joined(separator: ", "))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
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
