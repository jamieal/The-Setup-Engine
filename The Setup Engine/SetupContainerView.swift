import SwiftUI

struct SetupContainerView: View {
    @StateObject private var coordinator = SetupCoordinator()
    @ObservedObject private var shortcuts = AppShortcuts.shared

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                progressTrack

                Group {
                    switch coordinator.currentStep {
                    case .welcome:  WelcomeStep()
                    case .homebrew: HomebrewStep()
                    case .profile:  ProfileStep()
                    case .apps:     AppsStep()
                    case .system:   SystemStep()
                    case .review:   ReviewStep()
                    case .install:  InstallStep()
                    case .done:     DoneStep()
                    }
                }
                .id(coordinator.currentStep)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal:   .move(edge: .leading).combined(with: .opacity)
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .frame(minWidth: 760, minHeight: 620)
        .environmentObject(coordinator)
        .task {
            await coordinator.preflight()
        }
        .sheet(isPresented: $shortcuts.quickSearchOpen) {
            QuickSearchOverlay()
                .environmentObject(coordinator)
        }
        // Debug badge stays top-right (informational); help dropdown is bottom-left
        // (out of the way of the main content + footer buttons).
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            DebugBadge()
                .padding(12)
            #endif
        }
        .overlay(alignment: .bottomLeading) {
            HelpMenuButton()
                .padding(12)
        }
    }

    // MARK: - Progress Track

    @ViewBuilder
    private var progressTrack: some View {
        if coordinator.currentStep != .welcome && coordinator.currentStep != .done {
            HStack(spacing: 0) {
                ForEach(SetupCoordinator.Step.trackedSteps) { step in
                    let isPast    = step.rawValue < coordinator.currentStep.rawValue
                    let isCurrent = step == coordinator.currentStep

                    HStack(spacing: 8) {
                        Circle()
                            .fill(isPast || isCurrent ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 8, height: 8)

                        Text(step.trackTitle)
                            .font(.caption)
                            .fontWeight(isCurrent ? .semibold : .regular)
                            .foregroundStyle(isCurrent ? Color.primary
                                              : isPast    ? Color.accentColor
                                                          : Color.secondary)
                    }

                    if step != SetupCoordinator.Step.trackedSteps.last {
                        Rectangle()
                            .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .background(.regularMaterial)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if coordinator.currentStep != .welcome {
            HStack {
                if coordinator.canGoBack {
                    Button("Back") { coordinator.back() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }

                Spacer()

                primaryButton
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
            .background(.regularMaterial)
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch coordinator.currentStep {
        case .homebrew:
            switch coordinator.homebrewStatus {
            case .notInstalled, .failed:
                Button(coordinator.primaryActionTitle) {
                    Task { await coordinator.installHomebrew() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            case .installed:
                Button("Continue") { coordinator.next() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            default:
                Button(coordinator.primaryActionTitle) {}
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
            }

        case .done:
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

        default:
            Button(coordinator.primaryActionTitle) { coordinator.next() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!coordinator.canGoNext)
        }
    }
}

// MARK: - Hero

/// Centered hero header used by every step (large icon + title + subtitle).
struct StepHero: View {
    let symbol: String
    let title: String
    let subtitle: String
    var symbolGradient: [Color] = [.indigo, .blue]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: symbolGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(.bottom, 4)

            Text(title)
                .font(.system(size: 32, weight: .bold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 540)
        }
    }
}

#Preview {
    SetupContainerView()
}
