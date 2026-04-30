import SwiftUI

struct HomebrewStep: View {
    @EnvironmentObject var coordinator: SetupCoordinator
    @State private var showUninstallConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            switch coordinator.homebrewStatus {
            case .checking:
                checkingView
            case .installed:
                installedView
            case .notInstalled:
                notInstalledView
            case .installing:
                installingView
            case .uninstalling:
                uninstallingView
            case .failed(let message):
                failedView(message)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
        .task {
            if coordinator.homebrewStatus == .checking {
                await coordinator.checkHomebrew()
            }
        }
        .alert("Uninstall Homebrew?", isPresented: $showUninstallConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Uninstall", role: .destructive) {
                Task { await coordinator.uninstallHomebrew() }
            }
        } message: {
            Text("This removes /opt/homebrew and the brew shellenv line in your ~/.zprofile. Apps you installed via brew will not run anymore.")
        }
    }

    // MARK: - Variants

    private var checkingView: some View {
        VStack(spacing: 18) {
            ProgressView()
                .controlSize(.large)
            Text("Checking your Mac…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var installedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.green)

            Text("You're all set")
                .font(.system(size: 32, weight: .bold))

            Text("Homebrew is already installed.\nLet's pick what to install on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Uninstall Homebrew") {
                showUninstallConfirm = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red.opacity(0.8))
            .font(.caption)
            .padding(.top, 8)
        }
    }

    private var notInstalledView: some View {
        VStack(spacing: 24) {
            StepHero(
                symbol: "shippingbox",
                title: "Install Homebrew",
                subtitle: "We'll install Homebrew first — a free, open-source package manager that handles app installs."
            )

            HStack(spacing: 16) {
                trustCard(symbol: "lock.shield",      title: "Trusted",     subtitle: "Used by millions")
                trustCard(symbol: "arrow.down.circle", title: "Free",        subtitle: "No sign-up needed")
                trustCard(symbol: "leaf",             title: "Lightweight", subtitle: "Tiny footprint")
            }
            .frame(maxWidth: 600)

            VStack(spacing: 4) {
                Text("You'll be asked for your Mac password once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Link("Learn more about Homebrew",
                     destination: URL(string: "https://brew.sh")!)
                    .font(.caption)
            }
            .padding(.top, 4)
        }
    }

    private var installingView: some View {
        VStack(spacing: 22) {
            Image(systemName: "shippingbox")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.indigo, .blue], startPoint: .top, endPoint: .bottom)
                )

            Text("Installing Homebrew")
                .font(.system(size: 28, weight: .bold))

            Text(currentStage.label)
                .font(.title3)
                .foregroundStyle(.secondary)
                .animation(.easeInOut, value: currentStage)

            VStack(spacing: 8) {
                ProgressView(value: currentStage.progress)
                    .progressViewStyle(.linear)
                    .tint(.accentColor)
                    .frame(maxWidth: 460)

                HStack(spacing: 0) {
                    ForEach(BrewInstallStage.allCases) { stage in
                        VStack(spacing: 4) {
                            Image(systemName: stage.symbol(for: currentStage))
                                .font(.callout)
                                .foregroundStyle(stage.color(for: currentStage))
                            Text(stage.shortLabel)
                                .font(.caption2)
                                .foregroundStyle(stage.color(for: currentStage))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(maxWidth: 460)
            }

            Text("This usually takes a minute or two.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
    }

    private var uninstallingView: some View {
        VStack(spacing: 22) {
            Image(systemName: "trash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.red.opacity(0.85))

            Text("Uninstalling Homebrew")
                .font(.system(size: 28, weight: .bold))

            ProgressView()
                .controlSize(.large)
                .padding(.vertical, 4)

            Text("Removing /opt/homebrew and cleaning up your shell profile.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
        }
    }

    /// Picks the current install stage from explicit STAGE_X markers emitted by the script.
    private var currentStage: BrewInstallStage {
        let output = coordinator.shell.output
        if output.contains("INSTALL_OK")        { return .complete }
        if output.contains("STAGE_CONFIGURING") { return .configuring }
        if output.contains("STAGE_EXTRACTING")  { return .extracting }
        if output.contains("STAGE_DOWNLOADING") { return .downloading }
        return .preparing
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.orange)

            Text("Something went wrong")
                .font(.system(size: 28, weight: .bold))

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
    }

    // MARK: - Helpers

    private func trustCard(symbol: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
            Text(title)
                .font(.callout.weight(.semibold))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Install stages

enum BrewInstallStage: Int, CaseIterable, Identifiable, Equatable {
    case preparing
    case downloading
    case extracting
    case configuring
    case complete

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .preparing:   "Setting things up…"
        case .downloading: "Downloading Homebrew…"
        case .extracting:  "Extracting files…"
        case .configuring: "Configuring formulas…"
        case .complete:    "Almost done…"
        }
    }

    var shortLabel: String {
        switch self {
        case .preparing:   "Prep"
        case .downloading: "Download"
        case .extracting:  "Extract"
        case .configuring: "Configure"
        case .complete:    "Done"
        }
    }

    var progress: Double {
        Double(rawValue) / Double(BrewInstallStage.allCases.count - 1)
    }

    func symbol(for current: BrewInstallStage) -> String {
        if rawValue < current.rawValue { return "checkmark.circle.fill" }
        if self == current             { return "circle.inset.filled" }
        return "circle"
    }

    func color(for current: BrewInstallStage) -> Color {
        if rawValue < current.rawValue { return .green }
        if self == current             { return .accentColor }
        return .secondary.opacity(0.5)
    }
}

#Preview {
    HomebrewStep()
        .environmentObject(SetupCoordinator())
        .frame(width: 760, height: 540)
}
